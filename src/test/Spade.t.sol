// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {MockSpade} from "./mocks/MockSpade.sol";

import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract SpadeTest is DSTestPlus {
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


}
