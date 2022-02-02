// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Spade} from "../../Spade.sol";

/// @notice Mock Spade
/// @dev Only implement the tokenURI :)
/// @author andreas <andreas@nascent.xyz>
contract MockSpade is Spade {
    constructor(
      string memory _name,
      string memory _symbol,
      uint256 _depositAmount,
      uint256 _minPrice,
      uint256 _commitStart,
      uint256 _revealStart,
      uint256 _reservedMintStart,
      uint256 _publicMintStart,
      address _depositToken,
      uint256 _priceDecayPerBlock,
      uint256 _priceIncreasePerMint
    ) Spade(
      _name,
      _symbol,
      _depositAmount,
      _minPrice,
      _commitStart,
      _revealStart,
      _reservedMintStart,
      _publicMintStart,
      _depositToken,
      _priceDecayPerBlock,
      _priceIncreasePerMint
    ) {}

    function tokenURI(uint256) public pure virtual override returns (string memory) {}
}