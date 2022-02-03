// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {IERC20} from "./interfaces/IERC20.sol";
import {IERC721TokenReceiver} from "./interfaces/IERC721TokenReceiver.sol";

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";


/// ?????????????????????????????????????? . ######################################
/// ?????????????????????????????????????  %  #####################################
/// ????????????????????????????????????  %*:  ####################################
/// ???????????????????????????????????  %#*?:  ###################################
/// ?????????????????????????????????  ,%##*??:.  #################################
/// ???????????????????????????????  ,%##*?*#*??:.  ###############################
/// ?????????????????????????????  ,%###*??*##*???:.  #############################
/// ???????????????????????????  ,%####*???*###*????:.  ###########################
/// ?????????????????????????  ,%####**????*####**????:.  #########################
/// ???????????????????????  ,%#####**?????*#####**?????:.  #######################
/// ??????????????????????  %######**??????*######**??????:  ######################
/// ?????????????????????  %######**???????*#######**??????:  #####################
/// ????????????????????  %######***???????*#######***??????:  ####################
/// ????????????????????  %######***???????*#######***??????:  ####################
/// ????????????????????  %######***???????*#######***??????:  ####################
/// ?????????????????????  %######**??????***######**??????:  #####################
/// ??????????????????????  '%######****:^%*:^%****??????:'  ######################
/// ????????????????????????   '%####*:'  %*:  '%*????:'   ########################
/// ??????????????????????????           %#*?:           ##########################
/// ?????????????????????????????????  ,%##*??:.  #################################
/// ???????????????????????????????  .%###***???:.  ###############################
/// ??????????????????????????????                   ##############################
/// ???????????????????????????????????????*#######################################

/// @title SPADE
/// @author andreas <andreas@nascent.xyz>
/// @dev Extensible ERC721 Implementation with a baked-in commitment scheme and lbp.
abstract contract Spade {
    ///////////////////////////////////////////////////////////////////////////////
    ///                               CUSTOM ERRORS                             ///
    ///////////////////////////////////////////////////////////////////////////////

    error NotAuthorized();

    error WrongFrom();

    error InvalidRecipient();

    error UnsafeRecipient();

    error AlreadyMinted();

    error NotMinted();

    error InsufficientDeposit();

    error WrongPhase();

    error InvalidHash();

    error InsufficientPrice();

    error InsufficientValue();

    error InvalidAction();

    error SoldOut();

    error Outlier();

    ///////////////////////////////////////////////////////////////////////////////
    ///                                   EVENTS                                ///
    ///////////////////////////////////////////////////////////////////////////////

    event Commit(address indexed from, bytes32 commitment);

    event Reveal(address indexed from, uint256 appraisal);

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    event Approval(address indexed owner, address indexed spender, uint256 indexed tokenId);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    ///////////////////////////////////////////////////////////////////////////////
    ///                                  METADATA                               ///
    ///////////////////////////////////////////////////////////////////////////////

    string public name;

    string public symbol;

    function tokenURI(uint256 id) public view virtual returns (string memory);

    ///////////////////////////////////////////////////////////////////////////////
    ///                                  IMMUTABLES                             ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice The deposit amount to place a commitment
    uint256 public immutable depositAmount;

    /// @notice The minimum mint price
    uint256 public immutable minPrice;

    /// @notice Commit Start Timestamp
    uint256 public immutable commitStart;

    /// @notice Reveal Start Timestamp
    uint256 public immutable revealStart;

    /// @notice Restricted Mint Start Timestamp
    uint256 public immutable restrictedMintStart;

    /// @notice Public Mint Start Timestamp
    uint256 public immutable publicMintStart;

    /// @notice Optional ERC20 Deposit Token
    address public immutable depositToken;

    /// @notice LBP priceDecayPerBlock config
    uint256 public immutable priceDecayPerBlock;

    /// @notice LBP priceIncreasePerMint config
    uint256 public immutable priceIncreasePerMint;

    ///////////////////////////////////////////////////////////////////////////////
    ///                                  CONSTANTS                              ///
    ///////////////////////////////////////////////////////////////////////////////
    
    /// @dev The outlier scale for loss penalty
    /// @dev Loss penalty is taken with OUTLIER_FLEX * error as a percent
    uint256 public constant OUTLIER_FLEX = 5;

    /// @notice Flex is a scaling factor for standard deviation in price band calculation
    uint256 public constant FLEX = 1;

    /// @notice The maximum token supply
    uint256 public constant MAX_TOKEN_SUPPLY = 10_000;

    /// @notice The maximum loss penalty
    /// @dev Measured in bips
    uint256 public constant MAX_LOSS_PENALTY = 5_000;

    /// @notice The maximum discount factor
    /// @dev Measured in bips
    uint256 public constant MAX_DISCOUNT_FACTOR = 2_000;

    ///////////////////////////////////////////////////////////////////////////////
    ///                                CUSTOM STORAGE                           ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @dev The time stored for LBP implementation
    uint256 public mintTime;

    /// @notice A rolling variance calculation
    /// @dev Used for minting price bands
    uint256 public rollingVariance;

    /// @notice The number of commits calculated
    uint256 public count;

    /// @notice The result lbp start price
    uint256 public clearingPrice;

    /// @notice The total token supply
    uint256 public totalSupply;

    /// @notice User Commitments
    mapping(address => bytes32) public commits;

    /// @notice The resulting user appraisals
    mapping(address => uint256) public reveals;

    ///////////////////////////////////////////////////////////////////////////////
    ///                                ERC721 STORAGE                           ///
    ///////////////////////////////////////////////////////////////////////////////

    mapping(address => uint256) public balanceOf;

    mapping(uint256 => address) public ownerOf;

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    ///////////////////////////////////////////////////////////////////////////////
    ///                                 CONSTRUCTOR                             ///
    ///////////////////////////////////////////////////////////////////////////////

    constructor(
      string memory _name,
      string memory _symbol,
      uint256 _depositAmount,
      uint256 _minPrice,
      uint256 _commitStart,
      uint256 _revealStart,
      uint256 _restrictedMintStart,
      uint256 _publicMintStart,
      address _depositToken,
      uint256 _priceDecayPerBlock,
      uint256 _priceIncreasePerMint
    ) {
        name = _name;
        symbol = _symbol;

        // Store immutables
        depositAmount = _depositAmount;
        minPrice = _minPrice;
        commitStart = _commitStart;
        revealStart = _revealStart;
        restrictedMintStart = _restrictedMintStart;
        publicMintStart = _publicMintStart;
        depositToken = _depositToken;
        priceDecayPerBlock = _priceDecayPerBlock;
        priceIncreasePerMint = _priceIncreasePerMint;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                              COMMITMENT LOGIC                           ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Commit is payable to require the deposit amount
    function commit(bytes32 commitment) external payable {
        // Make sure the user has placed the deposit amount
        if (depositToken == address(0) && msg.value < depositAmount) revert InsufficientDeposit();
        
        // Verify during commit phase
        if (block.timestamp < commitStart || block.timestamp >= revealStart) revert WrongPhase();
        
        // Transfer the deposit token into this contract
        if (depositToken != address(0)) {
          IERC20(depositToken).transferFrom(msg.sender, address(this), depositAmount);
        }

        // Store Commitment
        commits[msg.sender] = commitment;

        // Emit the commit event
        emit Commit(msg.sender, commitment);
    }

    /// @notice Revealing a commitment
    function reveal(uint256 appraisal, bytes32 blindingFactor) external {
        // Verify during reveal+mint phase
        if (block.timestamp < revealStart || block.timestamp >= restrictedMintStart) revert WrongPhase();

        bytes32 senderCommit = commits[msg.sender];

        bytes32 calculatedCommit = keccak256(abi.encodePacked(msg.sender, appraisal, blindingFactor));

        if (senderCommit != calculatedCommit) revert InvalidHash();

        // The user has revealed their correct value
        delete commits[msg.sender];
        reveals[msg.sender] = appraisal;

        // Add the appraisal to the result value and recalculate variance
        // Calculation adapted from https://math.stackexchange.com/questions/102978/incremental-computation-of-standard-deviation
        if (count == 0) {
          clearingPrice = appraisal;
        } else {
          uint256 clearingPrice_ = clearingPrice;
          uint256 newClearingPrice = (count * clearingPrice_ + appraisal) / (count + 1);

          uint256 carryTerm = count * rollingVariance;
          uint256 clearingDiff = clearingPrice_ > newClearingPrice ?  clearingPrice_ - newClearingPrice : newClearingPrice - clearingPrice_;
          uint256 deviationUpdate = count * (clearingDiff ** 2);
          uint256 meanUpdate = appraisal < newClearingPrice ? newClearingPrice - appraisal : appraisal - newClearingPrice;
          uint256 updateTerm = meanUpdate ** 2;
          rollingVariance = (deviationUpdate + carryTerm + updateTerm) / (count + 1);

          // Update clearingPrice_ (new mean)
          clearingPrice = newClearingPrice;
        }
        unchecked {
          count += 1;
        }

        // Emit a Reveal Event
        emit Reveal(msg.sender, appraisal);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                           RESTRICTED MINT LOGIC                         ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Returns the mint price the user can mint at
    function restrictedMintPrice() external view returns(uint256 mintPrice) {
        // Sload the user's appraisal value
        uint256 senderAppraisal = reveals[msg.sender];

        // Result value
        uint256 finalValue = clearingPrice;
        if (finalValue < minPrice) finalValue = minPrice;

        // Calculate Parameters
        uint256 stdDev = FixedPointMathLib.sqrt(rollingVariance);
        uint256 clearingPrice_ = clearingPrice;
        uint256 diff = senderAppraisal < clearingPrice_ ? clearingPrice_ - senderAppraisal : senderAppraisal - clearingPrice_;

        // Prevent Outliers from Minting
        uint256 zscore = 0;
        if (stdDev != 0) {
          zscore = diff / stdDev;
        }

        // Calculate the discount to clearingPrice using an inverse relation to revealed price
        // Max discount factor = 20% or 2_000 bips
        // Prevent a zscore of 0
        zscore += 1;
        mintPrice = clearingPrice_ - (clearingPrice_ * MAX_DISCOUNT_FACTOR) / (10_000 * zscore);
    }

    /// @notice Enables Minting During the Restricted Minting Phase
    function restrictedMint() external payable {
        // Verify during mint phase
        if (block.timestamp < restrictedMintStart) revert WrongPhase();
        if (totalSupply >= MAX_TOKEN_SUPPLY) revert SoldOut();

        // Sload the user's appraisal value
        uint256 senderAppraisal = reveals[msg.sender];

        // Result value
        uint256 finalValue = clearingPrice;
        if (finalValue < minPrice) finalValue = minPrice;

        // Use Reveals as a mask
        if (reveals[msg.sender] == 0) revert InvalidAction();

        // Calculate Parameters
        uint256 stdDev = FixedPointMathLib.sqrt(rollingVariance);
        uint256 clearingPrice_ = clearingPrice;
        uint256 diff = senderAppraisal < clearingPrice_ ? clearingPrice_ - senderAppraisal : senderAppraisal - clearingPrice_;

        // Prevent Outliers from Minting
        uint256 zscore = 0;
        if (stdDev != 0) {
          zscore = diff / stdDev;
        } else {
          stdDev = 1;
        }
        if (zscore > 3) {
          revert Outlier();
        }

        // Calculate the discount to clearingPrice using an inverse relation to revealed price
        // Max discount factor = 20% or 2_000 bips
        // Prevent a zscore of 0
        zscore += 1;
        uint256 discountedPrice = clearingPrice_ - (clearingPrice_ * 2_000) / (10_000 * zscore);

        // Verify they sent at least enough to cover the mint cost
        if (depositToken == address(0) && msg.value < discountedPrice) revert InsufficientValue();
        if (depositToken != address(0)) IERC20(depositToken).transferFrom(msg.sender, address(this), discountedPrice);

        // Delete revealed value to prevent double spend
        delete reveals[msg.sender];

        // Deposit Penalty for underbidding
        uint256 depositReturn = depositAmount;
        if (senderAppraisal < clearingPrice_ && zscore >= 2) {
          depositReturn = depositReturn - (depositReturn * diff) / (stdDev * 100);
        }

        // Send deposit back to the minter
        if (depositToken == address(0)) msg.sender.call{value: depositReturn}("");
        else IERC20(depositToken).transfer(msg.sender, depositReturn);

        // Otherwise, we can mint the token
        unchecked {
          _mint(msg.sender, totalSupply++);
        }
    }

    /// @notice Forgos a mint
    /// @notice A penalty is assumed if the user's sealed bid was within the minting threshold
    function forgo() external {
        // Verify during mint phase
        if (block.timestamp < restrictedMintStart) revert WrongPhase();

        // Use Reveals as a mask
        if (reveals[msg.sender] == 0) revert InvalidAction();

        // Sload the user's appraisal value
        uint256 senderAppraisal = reveals[msg.sender];

        // sload depositAmount
        uint256 sloadDeposit = depositAmount;

        // Calculate a Loss penalty
        uint256 clearingPrice_ = clearingPrice;
        uint256 lossPenalty = 0;
        uint256 stdDev = FixedPointMathLib.sqrt(rollingVariance);
        uint256 diff = senderAppraisal < clearingPrice_ ? clearingPrice_ - senderAppraisal : senderAppraisal - clearingPrice_;
        uint256 zscore = 0;
        if (stdDev != 0) {
          zscore = diff / stdDev;
          lossPenalty = (zscore * sloadDeposit) / 100;
        }
        uint256 maxPenalty = (sloadDeposit * MAX_LOSS_PENALTY) / 10_000;
        // Use an outlier bounds of 2 - realistically it should be 3
        if (zscore >= 2 || lossPenalty > maxPenalty) {
          lossPenalty = maxPenalty;
        }

        // This won't underflow unless the MAX_LOSS_PENALY was misconfigured
        uint256 amountTransfer = sloadDeposit - lossPenalty;

        // Transfer eth or erc20 back to user
        delete reveals[msg.sender];
        if(depositToken == address(0)) msg.sender.call{value: amountTransfer}("");
        else IERC20(depositToken).transfer(msg.sender, amountTransfer);
    }

    /// @notice Allows a user to withdraw their deposit on reveal elusion
    function lostReveal() external {
        // Verify after the reveal phase
        if (block.timestamp < restrictedMintStart) revert WrongPhase();

        // Prevent withdrawals unless reveals is empty and commits isn't
        if (reveals[msg.sender] != 0 || commits[msg.sender] == 0) revert InvalidAction();
    
        // Then we can release deposit with the maximum loss penalty
        delete commits[msg.sender];
        uint256 lossyDeposit = depositAmount;
        lossyDeposit = lossyDeposit - ((lossyDeposit * MAX_LOSS_PENALTY) / 10_000);
        if(depositToken == address(0)) msg.sender.call{value: lossyDeposit}("");
        else IERC20(depositToken).transfer(msg.sender, lossyDeposit);
    }

    /// @notice Allows a user to view if they can mint
    function canRestrictedMint() external view returns (bool mintable) {
      // Sload the user's appraisal value
      uint256 senderAppraisal = reveals[msg.sender];
      
      // Get find the standard deviation
      uint256 stdDev = FixedPointMathLib.sqrt(rollingVariance);

      // Calculate Absolute Difference
      uint256 clearingPrice_ = clearingPrice;
      uint256 diff = senderAppraisal < clearingPrice_ ? clearingPrice_ - senderAppraisal : senderAppraisal - clearingPrice_;

      // Outliers can't mint, everyone else can at varying discounts
      uint256 zscore = 0;
      if (stdDev != 0) {
        zscore = diff / stdDev;
      }
      mintable = block.timestamp >= restrictedMintStart
                  && zscore < 3
                  && ((totalSupply + 1) <= MAX_TOKEN_SUPPLY)
                  && senderAppraisal != 0;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                              PUBLIC LBP LOGIC                           ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Permissionless minting for non-commitment phase participants
    /// @param amount The number of ERC721 tokens to mint
    function mint(uint256 amount) external payable {
        if (block.timestamp < publicMintStart) revert WrongPhase();
        if (totalSupply >= MAX_TOKEN_SUPPLY) revert SoldOut();

        // Calculate the mint price
        uint256 memMintTime = mintTime;
        if (memMintTime == 0) memMintTime = block.timestamp;
        uint256 decay = ((block.timestamp - memMintTime) * priceDecayPerBlock);
        uint256 mintPrice = 0;
        if (decay <= clearingPrice) mintPrice = clearingPrice - decay;
        if (mintPrice < minPrice) mintPrice = minPrice;

        // Take Payment
        if (depositToken == address(0) && msg.value < (mintPrice * amount)) revert InsufficientValue();
        if (depositToken != address(0)) {
          IERC20(depositToken).transferFrom(msg.sender, address(this), mintPrice * amount);
        }

        // Mint and Update
        for (uint256 i = 0; i < amount; i++) {
          _safeMint(msg.sender, totalSupply++);
          // unchecked {
          // }
        }
        clearingPrice = mintPrice + priceIncreasePerMint * amount;
        mintTime = block.timestamp;
    }

    /// @notice Returns the price to mint for the LBP
    /// @param amount The number of tokens to mint
    /// @return price to mint the tokens
    function mintPrice(uint256 amount) external view returns (uint256 price) {
      uint256 diff = 0;
      if (mintTime != 0) diff = block.timestamp - mintTime;
      uint256 decay = (diff * priceDecayPerBlock);
      if (decay <= clearingPrice) price = clearingPrice - decay;
      if (price < minPrice) price = minPrice;
      price = price * amount;
    }

    /// @notice Allows a user to view if they can mint
    /// @param amount The amount of tokens to mint
    /// @return allowed If the sender is allowed to mint
    function canMint(uint256 amount) external view returns (bool allowed) {
      allowed = block.timestamp >= publicMintStart && (totalSupply + amount) < MAX_TOKEN_SUPPLY;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                                ERC721 LOGIC                             ///
    ///////////////////////////////////////////////////////////////////////////////

    function approve(address spender, uint256 id) public virtual {
        address owner = ownerOf[id];

        if (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) {
          revert NotAuthorized();
        }

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        if (from != ownerOf[id]) revert WrongFrom();

        if (to == address(0)) revert InvalidRecipient();

        if (msg.sender != from && msg.sender != getApproved[id] && !isApprovedForAll[from][msg.sender]) {
          revert NotAuthorized();
        }

        // Underflow impossible due to check for ownership
        unchecked {
            balanceOf[from]--;
            balanceOf[to]++;
        }

        ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        if (
          to.code.length != 0 &&
          IERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") !=
          IERC721TokenReceiver.onERC721Received.selector
        ) {
          revert UnsafeRecipient();
        }
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes memory data
    ) public virtual {
        transferFrom(from, to, id);

        if (
          to.code.length != 0 &&
          IERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data) !=
          IERC721TokenReceiver.onERC721Received.selector
        ) {
          revert UnsafeRecipient();
        }
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                                ERC165 LOGIC                             ///
    ///////////////////////////////////////////////////////////////////////////////

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f;   // ERC165 Interface ID for ERC721Metadata
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               INTERNAL LOGIC                            ///
    ///////////////////////////////////////////////////////////////////////////////

    function _mint(address to, uint256 id) internal virtual {
        if (to == address(0)) revert InvalidRecipient();

        if (ownerOf[id] != address(0)) revert AlreadyMinted();

        // Counter overflow is incredibly unrealistic.
        unchecked {
            balanceOf[to]++;
        }

        ownerOf[id] = to;

        emit Transfer(address(0), to, id);
    }

    function _burn(uint256 id) internal virtual {
        address owner = ownerOf[id];

        if (ownerOf[id] == address(0)) revert NotMinted();

        // Ownership check above ensures no underflow.
        unchecked {
            balanceOf[owner]--;
        }

        delete ownerOf[id];

        delete getApproved[id];

        emit Transfer(owner, address(0), id);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                            INTERNAL SAFE LOGIC                          ///
    ///////////////////////////////////////////////////////////////////////////////

    function _safeMint(address to, uint256 id) internal virtual {
        _mint(to, id);

        if (
          to.code.length != 0 &&
          IERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, "") !=
          IERC721TokenReceiver.onERC721Received.selector
        ) {
          revert UnsafeRecipient();
        }
    }

    function _safeMint(
        address to,
        uint256 id,
        bytes memory data
    ) internal virtual {
        _mint(to, id);

        if (
          to.code.length != 0 &&
          IERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, data) !=
          IERC721TokenReceiver.onERC721Received.selector
        ) {
          revert UnsafeRecipient();
        }
    }
}