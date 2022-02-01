// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Spade, ERC721TokenReceiver} from "../../Spade.sol";

contract ERC721User is ERC721TokenReceiver {
    Spade spade;

    constructor(Spade _spade) {
        spade = _spade;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }

    function approve(address spender, uint256 tokenId) public virtual {
        spade.approve(spender, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        spade.setApprovalForAll(operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual {
        spade.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual {
        spade.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        spade.safeTransferFrom(from, to, tokenId, data);
    }
}