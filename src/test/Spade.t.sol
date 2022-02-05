// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {MockSpade} from "./mocks/MockSpade.sol";
import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {ERC721User} from "./mocks/MockReceiver.sol";

import {stdError, stdStorage, StdStorage} from "@std/stdlib.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

contract SpadeTest is DSTestPlus {
    using stdStorage for StdStorage;
    StdStorage stdstore;

    MockSpade spade;

    // Spade Arguments and Metadata
    string public name = "MockSpade";
    string public symbol = "SPADE";
    uint256 public depositAmount = 100;
    uint256 public minPrice = 10;
    uint256 public creationTime = block.timestamp;
    uint256 public commitStart = creationTime + 10;
    uint256 public revealStart = creationTime + 20;
    uint256 public restrictedMintStart = creationTime + 30;
    uint256 public publicMintStart = creationTime + 40;
    address public depositToken = address(0);
    uint256 public priceDecayPerBlock = 1;
    uint256 public priceIncreasePerMint = 1;

    ERC721User public receiver;

    bytes32 public blindingFactor = bytes32(bytes("AllTheCoolKidsHateTheDiamondPattern"));

    function setUp() public {
        spade = new MockSpade(
            name,                   // string memory _name,
            symbol,                 // string memory _symbol,
            depositAmount,          // uint256 _depositAmount,
            minPrice,               // uint256 _minPrice,
            commitStart,            // uint256 _commitStart,
            revealStart,            // uint256 _revealStart,
            restrictedMintStart,    // uint256 _restrictedMintStart,
            publicMintStart,        // uint256 _publicMintStart
            depositToken,           // address _depositToken,
            priceDecayPerBlock,     // uint256 _priceDecayPerBlock
            priceIncreasePerMint    // uint256 _priceIncreasePerMint
        );

        receiver = new ERC721User(spade);
    }

    /// @notice Tests metadata and immutable config
    function testConfig() public {
        // Metadata
        assert(keccak256(abi.encodePacked((spade.name()))) == keccak256(abi.encodePacked((name))));
        assert(keccak256(abi.encodePacked((spade.symbol()))) == keccak256(abi.encodePacked((symbol))));

        // Immutables
        assert(spade.depositAmount() == depositAmount);
        assert(spade.minPrice() == minPrice);
        assert(spade.commitStart() == commitStart);
        assert(spade.revealStart() == revealStart);
        assert(spade.restrictedMintStart() == restrictedMintStart);
        assert(spade.publicMintStart() == publicMintStart);
        assert(spade.depositToken() == depositToken);
        assert(spade.priceDecayPerBlock() == priceDecayPerBlock);
        assert(spade.priceIncreasePerMint() == priceIncreasePerMint);

        // Constants
        assert(spade.OUTLIER_FLEX() == 5);
        assert(spade.FLEX() == 1);
        assert(spade.MAX_TOKEN_SUPPLY() == 10_000);
        assert(spade.MAX_LOSS_PENALTY() == 5_000);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               COMMIT LOGIC                              ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Test Commitments
    function testCommit() public {
        bytes32 commitment = keccak256(abi.encodePacked(address(this), uint256(10), blindingFactor));

        // Expect Revert when we don't send at least the depositAmount
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InsufficientDeposit()"))));
        spade.commit(commitment);

        // Expect Revert when we are not in the commit phase
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("WrongPhase()"))));
        spade.commit{value: depositAmount}(commitment);

        // Jump to after the commit phase
        vm.warp(revealStart);

        // Expect Revert when we are not in the commit phase
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("WrongPhase()"))));
        spade.commit{value: depositAmount}(commitment);

        // Jump to during the commit phase
        vm.warp(commitStart);

        // Successfully Commit
        spade.commit{value: depositAmount}(commitment);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               REVEAL LOGIC                              ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Test Reveals
    function testReveal(uint256 invalidConcealedBid) public {
        // Create a Successful Commitment
        bytes32 commitment = keccak256(abi.encodePacked(address(this), uint256(10), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment);

        // Fail to reveal pre-reveal phase
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("WrongPhase()"))));
        spade.reveal(uint256(10), blindingFactor);

        // Fail to reveal post-reveal phase
        vm.warp(restrictedMintStart);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("WrongPhase()"))));
        spade.reveal(uint256(10), blindingFactor);

        // Warp to the reveal phase
        vm.warp(revealStart);

        // Fail to reveal with invalid value
        uint256 concealed = invalidConcealedBid != 10 ? invalidConcealedBid : 11;
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InvalidHash()"))));
        spade.reveal(uint256(concealed), blindingFactor);

        // Successfully Reveal During Reveal Phase
        spade.reveal(uint256(10), blindingFactor);

        // We shouldn't be able to double reveal
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InvalidHash()"))));
        spade.reveal(uint256(10), blindingFactor);

        // Validate Price and Variance Calculations
        assert(spade.clearingPrice() == uint256(10));
        assert(spade.count() == uint256(1));
    }

    /// @notice Test Multiple Reveals
    function testMultipleReveals() public {
        // Create a Successful Commitment and Reveal
        bytes32 commitment = keccak256(abi.encodePacked(address(this), uint256(10), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment);
        vm.warp(revealStart);
        spade.reveal(uint256(10), blindingFactor);

        // Validate Price and Variance Calculations
        assert(spade.clearingPrice() == uint256(10));
        assert(spade.count() == uint256(1));

        // Initiate Hoax
        startHoax(address(1337), address(1337), type(uint256).max);

        // Create Another Successful Commitment and Reveal
        bytes32 commitment2 = keccak256(abi.encodePacked(address(1337), uint256(20), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment2);
        vm.warp(revealStart);
        spade.reveal(uint256(20), blindingFactor);

        // Validate Price and Variance Calculations
        assert(spade.clearingPrice() == uint256(15));
        assert(spade.count() == uint256(2));
        assert(spade.rollingVariance() == uint256(25));
        
        // Stop Hoax (prank under-the-hood)
        vm.stopPrank();

        // Initiate Another Hoax
        startHoax(address(420), address(420), type(uint256).max);

        // Create Another Successful Commitment and Reveal
        bytes32 commitment3 = keccak256(abi.encodePacked(address(420), uint256(30), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment3);
        vm.warp(revealStart);
        spade.reveal(uint256(30), blindingFactor);

        // Validate Price and Variance Calculations
        assert(spade.clearingPrice() == uint256(20));
        assert(spade.count() == uint256(3));
        assert(spade.rollingVariance() == uint256(66));
        
        // Stop Hoax (prank under-the-hood)
        vm.stopPrank();
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                          RESTRICTED MINT LOGIC                          ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Test Restricted Minting
    function testRestrictedMinting() public {
        // Commit+Reveal 1
        bytes32 commitment = keccak256(abi.encodePacked(address(this), uint256(10), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment);
        vm.warp(revealStart);
        spade.reveal(uint256(10), blindingFactor);

        // Minting fails outside restricted minting phase
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("WrongPhase()"))));
        spade.restrictedMint();
        assert(spade.canRestrictedMint() == false);

        // Mint should fail without value
        vm.warp(restrictedMintStart);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InsufficientValue()"))));
        spade.restrictedMint();

        // The expected discount is 2_000 bips
        assert(spade.restrictedMintPrice() == 8);

        // Check parameters
        assert(spade.clearingPrice() == 10);
        assert(spade.rollingVariance() == 0);

        // We should be able to mint
        assert(spade.canRestrictedMint() == true);
        spade.restrictedMint{value: 8}();
        assert(spade.reveals(address(this)) == 0);
        assert(spade.balanceOf(address(this)) == 1);
        assert(spade.totalSupply() == 1);

        // Double mints are prevented with Reveals Mask
        assert(spade.canRestrictedMint() == false);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InvalidAction()"))));
        spade.restrictedMint{value: 8}();
    }

    /// @notice Test Multiple Restricted Mints
    function testMultipleRestrictedMints() public {
        // Commit+Reveal 1
        bytes32 commitment = keccak256(abi.encodePacked(address(this), uint256(10), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment);
        vm.warp(revealStart);
        spade.reveal(uint256(10), blindingFactor);

        // Commit+Reveal 2
        startHoax(address(1337), address(1337), type(uint256).max);
        bytes32 commitment2 = keccak256(abi.encodePacked(address(1337), uint256(20), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment2);
        vm.warp(revealStart);
        spade.reveal(uint256(20), blindingFactor);
        vm.stopPrank();

        // Commit+Reveal 3
        startHoax(address(420), address(420), type(uint256).max);
        bytes32 commitment3 = keccak256(abi.encodePacked(address(420), uint256(30), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment3);
        vm.warp(revealStart);
        spade.reveal(uint256(30), blindingFactor);
        vm.stopPrank();

        // Commit+Reveal 4
        startHoax(address(69), address(69), type(uint256).max);
        bytes32 commitment4 = keccak256(abi.encodePacked(address(69), uint256(40), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment4);
        vm.warp(revealStart);
        spade.reveal(uint256(40), blindingFactor);
        vm.stopPrank();

        // Commit+Reveal 5
        startHoax(address(2), address(2), type(uint256).max);
        bytes32 commitment5 = keccak256(abi.encodePacked(address(2), uint256(60), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment5);
        vm.warp(revealStart);
        spade.reveal(uint256(60), blindingFactor);
        vm.stopPrank();

        // Can't mint outside restrictedMintPhase
        assert(spade.canRestrictedMint() == false);

        // Check parameters
        assert(spade.clearingPrice() == 32);
        assert(spade.rollingVariance() == 295);

        // Mint should fail without value
        vm.warp(restrictedMintStart);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InsufficientValue()"))));
        spade.restrictedMint();

        // Check Expected Discounts
        // The commitments closest to the clearingPrice should have a lower mint price
        assert(spade.restrictedMintPrice() == 29);
        startHoax(address(1337), address(1337), type(uint256).max);
        assert(spade.restrictedMintPrice() == 26);
        vm.stopPrank();
        startHoax(address(420), address(420), type(uint256).max);
        assert(spade.restrictedMintPrice() == 26);
        vm.stopPrank();
        startHoax(address(69), address(69), type(uint256).max);
        assert(spade.restrictedMintPrice() == 26);
        vm.stopPrank();
        startHoax(address(2), address(2), type(uint256).max);
        assert(spade.restrictedMintPrice() == 29);
        vm.stopPrank();

        // We should be able to mint
        assert(spade.canRestrictedMint() == true);
        spade.restrictedMint{value: 29}();
        assert(spade.reveals(address(this)) == 0);
        assert(spade.balanceOf(address(this)) == 1);
        assert(spade.totalSupply() == 1);

        // Double mints are prevented with Reveals Mask
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InvalidAction()"))));
        spade.restrictedMint{value: 29}();

        // Next user mints
        startHoax(address(1337), address(1337), type(uint256).max);
        vm.warp(restrictedMintStart);
        spade.restrictedMint{value: 26}();
        assert(spade.balanceOf(address(1337)) == 1);
        assert(spade.totalSupply() == 2);
        vm.stopPrank();

        // Third user mints
        startHoax(address(420), address(420), type(uint256).max);
        vm.warp(restrictedMintStart);
        spade.restrictedMint{value: 26}();
        assert(spade.balanceOf(address(420)) == 1);
        assert(spade.totalSupply() == 3);
        vm.stopPrank();

        // Fourth user mints
        startHoax(address(69), address(69), type(uint256).max);
        vm.warp(restrictedMintStart);
        spade.restrictedMint{value: 26}();
        assert(spade.balanceOf(address(69)) == 1);
        assert(spade.totalSupply() == 4);
        vm.stopPrank();

        // Fifth user mints
        startHoax(address(2), address(2), type(uint256).max);
        vm.warp(restrictedMintStart);
        spade.restrictedMint{value: 29}();
        assert(spade.balanceOf(address(2)) == 1);
        assert(spade.totalSupply() == 5);
        vm.stopPrank();
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                                FORGO LOGIC                              ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Test Forgos
    function testForgo() public {
        // Commit+Reveal
        bytes32 commitment = keccak256(abi.encodePacked(address(this), uint256(10), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment);
        vm.warp(revealStart);
        spade.reveal(uint256(10), blindingFactor);

        // Forgo fails outside mint phase
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("WrongPhase()"))));
        spade.forgo();

        vm.warp(restrictedMintStart);

        // Random User can't forgo
        startHoax(address(69), address(69), type(uint256).max);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InvalidAction()"))));
        spade.forgo();
        vm.stopPrank();

        // We should be able to forgo
        assert(spade.reveals(address(this)) != 0);
        spade.forgo();
        assert(spade.reveals(address(this)) == 0);
        assert(spade.balanceOf(address(this)) == 0);
        assert(spade.totalSupply() == 0);

        // Double forgos are prevented with Reveals Mask
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InvalidAction()"))));
        spade.forgo();
    }

    /// @notice Test Outliers Forgos
    function testOutlierForgo() public {
        startHoax(address(420), address(420), depositAmount);
        bytes32 commitment = keccak256(abi.encodePacked(address(420), uint256(1), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment);
        vm.warp(revealStart);
        spade.reveal(uint256(1), blindingFactor);
        vm.stopPrank();

        startHoax(address(421), address(421), depositAmount);
        bytes32 commitment2 = keccak256(abi.encodePacked(address(421), uint256(1), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment2);
        vm.warp(revealStart);
        spade.reveal(uint256(1), blindingFactor);
        vm.stopPrank();

        startHoax(address(422), address(422), depositAmount);
        bytes32 commitment3 = keccak256(abi.encodePacked(address(422), uint256(1), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment3);
        vm.warp(revealStart);
        spade.reveal(uint256(1), blindingFactor);
        vm.stopPrank();

        startHoax(address(423), address(423), depositAmount);
        bytes32 commitment4 = keccak256(abi.encodePacked(address(423), uint256(1), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment4);
        vm.warp(revealStart);
        spade.reveal(uint256(1), blindingFactor);
        vm.stopPrank();

        startHoax(address(69), address(69), depositAmount);
        bytes32 commitment5 = keccak256(abi.encodePacked(address(69), uint256(100), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment5);
        vm.warp(revealStart);
        spade.reveal(uint256(100), blindingFactor);
        vm.stopPrank();

        // Check params
        // Variance = 1568.16
        // Standard Deviation = 39.6
        // Mean = 20.8

        assert(spade.rollingVariance() == 1568);
        uint256 stdDev = FixedPointMathLib.sqrt(1568);
        assert(stdDev == 39);
        uint256 clearingPrice = spade.clearingPrice();
        assert(clearingPrice == 20);
        uint256 senderAppraisal = spade.reveals(address(69));
        assert(senderAppraisal == 100);
        uint256 diff = senderAppraisal < clearingPrice ? clearingPrice - senderAppraisal : senderAppraisal - clearingPrice;
        uint256 zscore = diff / stdDev;
        uint256 lossPenalty = (zscore * depositAmount) / 100;
        assert(diff == 80);
        assert(zscore == 2);

        // Jump to mint
        vm.warp(restrictedMintStart);

        // 100 should lose the max penalty since they're an outlier
        startHoax(address(69), address(69), 0);
        spade.forgo();
        uint256 remainingBalance = depositAmount - (spade.MAX_LOSS_PENALTY() * depositAmount) / 10_000;
        assert(address(69).balance == remainingBalance);
        assert(spade.reveals(address(69)) == 0);
        assert(spade.balanceOf(address(69)) == 0);
        assert(spade.totalSupply() == 0);
        vm.stopPrank();
    }

    /// @notice Test Multiple Forgos
    function testMultipleForgos() public {
        // Commit+Reveal 1
        bytes32 commitment = keccak256(abi.encodePacked(address(this), uint256(10), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment);
        vm.warp(revealStart);
        spade.reveal(uint256(10), blindingFactor);

        // Commit+Reveal 2
        startHoax(address(1337), address(1337), type(uint256).max);
        bytes32 commitment2 = keccak256(abi.encodePacked(address(1337), uint256(20), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment2);
        vm.warp(revealStart);
        spade.reveal(uint256(20), blindingFactor);
        vm.stopPrank();

        // Commit+Reveal 3
        startHoax(address(420), address(420), type(uint256).max);
        bytes32 commitment3 = keccak256(abi.encodePacked(address(420), uint256(30), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment3);
        vm.warp(revealStart);
        spade.reveal(uint256(30), blindingFactor);
        vm.stopPrank();

        // Forgo fails outside mint phase
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("WrongPhase()"))));
        spade.forgo();

        // We should be able to forgo
        vm.warp(restrictedMintStart);
        assert(spade.reveals(address(this)) != 0);
        spade.forgo();
        assert(spade.reveals(address(this)) == 0);
        assert(spade.balanceOf(address(this)) == 0);
        assert(spade.totalSupply() == 0);

        // Double forgos are prevented with Reveals Mask
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InvalidAction()"))));
        spade.forgo();

        // Next user forgos
        startHoax(address(1337), address(1337), type(uint256).max);
        spade.forgo();
        assert(spade.balanceOf(address(1337)) == 0);
        assert(spade.totalSupply() == 0);
        vm.stopPrank();

        // Third user forgos
        startHoax(address(420), address(420), type(uint256).max);
        spade.forgo();
        assert(spade.balanceOf(address(420)) == 0);
        assert(spade.totalSupply() == 0);
        vm.stopPrank();
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                                LOST REVEALS                             ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Tests deposit withdrawals on reveal miss
    function testLostReveal() public {
        startHoax(address(69), address(69), depositAmount);
        bytes32 commitment = keccak256(abi.encodePacked(address(this), uint256(10), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment);
        vm.warp(revealStart);

        // Should fail to withdraw since still reveal phase
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("WrongPhase()"))));
        spade.lostReveal();

        // Skip reveal and withdraw
        assert(address(69).balance == 0);
        vm.warp(restrictedMintStart);
        spade.lostReveal();
        assert(address(69).balance == (spade.MAX_LOSS_PENALTY() * depositAmount) / 10_000);

        // We shouldn't be able to withdraw again since commitment is gone
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InvalidAction()"))));
        spade.lostReveal(); 
        vm.stopPrank();
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                              PUBLIC LBP LOGIC                           ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Test Public Minting
    function testPublicMinting() public {
        // Commit+Reveal 1
        startHoax(address(69), address(69), depositAmount);
        bytes32 commitment = keccak256(abi.encodePacked(address(69), uint256(10), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment);
        vm.warp(revealStart);
        spade.reveal(uint256(10), blindingFactor);
        vm.stopPrank();

        // Minting fails outside restricted minting phase
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("WrongPhase()"))));
        spade.mint(1);
        assert(spade.canRestrictedMint() == false);

        // Mint should fail in restricted phase
        vm.warp(restrictedMintStart);
        assert(spade.canRestrictedMint() == false);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("WrongPhase()"))));
        spade.mint(1);

        // Mint should fail in restricted phase
        vm.warp(publicMintStart);
        assert(spade.canRestrictedMint() == false);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InsufficientValue()"))));
        spade.mint(1);

        // We should be able to mint now
        assert(spade.canMint(1) == true);

        // Check parameters
        assert(spade.clearingPrice() == 10);
        assert(spade.rollingVariance() == 0);
        assert(spade.mintTime() == 0);
        assert(spade.priceDecayPerBlock() == priceDecayPerBlock);
        assert(spade.priceIncreasePerMint() == priceIncreasePerMint);

        // Get the public mint price
        assert(spade.mintPrice(1) == 10);
        assert(spade.mintPrice(10) == 100);

        // We can't mint from this contract since it doesn't implement ERC721 Token Receiver
        // vm.expectRevert(abi.encodePacked(bytes4(keccak256("UnsafeRecipient()"))));
        // spade.mint{value: 10}(1);

        // We can mint from a token receiver context
        startHoax(address(receiver), address(receiver), type(uint256).max);
        spade.mint{value: 10}(1);
        assert(spade.balanceOf(address(receiver)) == 1);
        assert(spade.totalSupply() == 1);

        // The clearing price should be bumped up since it's an LBP
        assert(spade.clearingPrice() == 11);
        assert(spade.mintPrice(1) == 11);
        
        // Double mints are allowed in the public LBP phase
        spade.mint{value: 11}(1);
        assert(spade.balanceOf(address(receiver)) == 2);
        assert(spade.totalSupply() == 2);
        assert(spade.clearingPrice() == 12);
        assert(spade.mintPrice(1) == 12);

        // Jump one block ahead to realize price decrease
        vm.warp(publicMintStart + 1);

        // Price doesn't decrease since we aren't in the next block
        assert(spade.mintPrice(1) == 12);
        spade.mint{value: 12}(1);
        assert(spade.balanceOf(address(receiver)) == 3);
        assert(spade.totalSupply() == 3);
        assert(spade.clearingPrice() == 13);
        assert(spade.mintPrice(1) == 13);

        // Roll into the future
        vm.roll(publicMintStart + 1);

        // Mint at a decreased price
        assert(spade.mintPrice(1) == 13);
        spade.mint{value: 13}(1);
        assert(spade.balanceOf(address(receiver)) == 4);
        assert(spade.totalSupply() == 4);
        assert(spade.clearingPrice() == 14);
        assert(spade.mintPrice(1) == 14);

        // Roll into the future
        vm.roll(publicMintStart + 5);

        // The price should now be the min price
        assert(spade.mintPrice(1) == minPrice);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("InsufficientValue()"))));
        spade.mint{value: 9}(1);
        spade.mint{value: 10}(1);
        assert(spade.balanceOf(address(receiver)) == 5);
        assert(spade.totalSupply() == 5);
        assert(spade.clearingPrice() == 11);
        assert(spade.mintPrice(1) == 11);

        vm.stopPrank();
    }

    /// @notice Test Max Public Minting
    function testPublicMintingMax() public {
        // Commit+Reveal 1
        startHoax(address(69), address(69), depositAmount);
        bytes32 commitment = keccak256(abi.encodePacked(address(69), uint256(10), blindingFactor));
        vm.warp(commitStart);
        spade.commit{value: depositAmount}(commitment);
        vm.warp(revealStart);
        spade.reveal(uint256(10), blindingFactor);
        vm.stopPrank();

        // Mint should fail in restricted phase
        vm.warp(publicMintStart);

        // We should be able to mint now
        assert(spade.canMint(1) == true);

        // We can mint from a token receiver context
        uint256 maxMintAmount = spade.MAX_MINT_PER_ACCOUNT();
        uint256 inialClearingPrice = spade.clearingPrice();
        startHoax(address(receiver), address(receiver), type(uint256).max);

        // We should be able to mint the max amount
        assert(spade.canMint(maxMintAmount) == true);

        // Mint
        spade.mint{value: 10 * maxMintAmount}(maxMintAmount);
        assert(spade.balanceOf(address(receiver)) == maxMintAmount);
        assert(spade.totalSupply() == maxMintAmount);

        // The clearing price should be bumped up since it's an LBP
        assert(spade.clearingPrice() == inialClearingPrice + maxMintAmount);
        assert(spade.mintPrice(1) == inialClearingPrice + maxMintAmount);
        
        // We can't mint more than the maximum amount
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("MaxTokensMinted()"))));
        spade.mint{value: inialClearingPrice + maxMintAmount}(1);

        // We shouldn't be able to mint
        assert(spade.canMint(1) == false);

        vm.stopPrank();
    }

    /// @notice Test max supply limit
    function testMaxSupply() public {
        uint256 maxSupply = spade.MAX_TOKEN_SUPPLY();
        uint256 maxMint = spade.MAX_MINT_PER_ACCOUNT();

        // Modify totalSupply to simulate (maxMint - 1) available
        stdstore.target(address(spade)).sig("totalSupply()").checked_write(
            maxSupply - (maxMint - 1)
        );

        // Time travel to public mint timestamp
        vm.warp(spade.publicMintStart());
        
        // Initiate hoax to mint as 'receiver'
        startHoax(address(receiver), address(receiver), type(uint256).max);

        // Minting `maxMint` should fail as SoldOut
        uint256 mintPrice = spade.mintPrice(maxMint);
        assert(spade.canMint(maxMint) == false);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("SoldOut()"))));
        spade.mint{value: mintPrice}(maxMint);

        // Minting `maxMint - 1` should succeed
        mintPrice = spade.mintPrice(maxMint - 1);
        assert(spade.canMint(maxMint - 1) == true);
        spade.mint{value: mintPrice}(maxMint - 1);

        vm.stopPrank();

        // Should have minted exactly total supply
        assert(spade.totalSupply() == maxSupply);
    }
}
