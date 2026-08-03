// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/*
 *  ██████╗ ██████╗  ██████╗    ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗
 * ██╔════╝██╔═══██╗██╔════╝    ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║
 * ██║     ██║   ██║██║            ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║
 * ██║     ██║   ██║██║            ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║
 * ╚██████╗╚██████╔╝╚██████╗       ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║
 *  ╚═════╝ ╚═════╝  ╚═════╝       ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝
 *
 * COC TOKEN (COCT)
 * BEP20 · 18 dp · fixed 1B supply
 *
 * Fixed supply — the entire 1,000,000,000 COCT is minted to the deployer at construction; there is NO
 * mint function, so supply can never inflate. BEP20 is ERC20-compatible (bool-returning transfers,
 * 18 decimals) — no BSC-specific interface is required for wallets/BscScan.
 *
 * Ownership is RENOUNCED in the constructor: `owner()` returns address(0) immediately after deployment, so
 * anyone can verify on-chain (BscScan / wallets) that the token has no admin — no owner-gated levers exist,
 * and none can ever be added. Inherits OpenZeppelin `Ownable` purely to expose the standard `owner()` view.
 *
 * Deployed on BSC mainnet at 0x13c6f832A8eA9D450FBc04c73b59D2A66ae12A77 (COCT).
 */

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract COCToken is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    constructor() ERC20("COC TOKEN", "COCT") Ownable(msg.sender) {
        _mint(msg.sender, MAX_SUPPLY);
        renounceOwnership();
    }
}
