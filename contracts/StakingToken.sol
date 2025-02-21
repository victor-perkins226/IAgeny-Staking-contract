// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingToken is ERC20, Ownable {
    // Initialize with a name and symbol
    constructor(string memory name, string memory symbol) 
        ERC20(name, symbol) 
        Ownable(msg.sender)
    {
        _mint(msg.sender, 100000000 * 1e18);
    }

    // Mint function - only owner can mint new tokens
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // Optional: Add burn functionality
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    // Optional: Add burnFrom functionality (requires approval)
    function burnFrom(address account, uint256 amount) public {
        uint256 currentAllowance = allowance(account, msg.sender);
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        unchecked {
            _approve(account, msg.sender, currentAllowance - amount);
        }
        _burn(account, amount);
    }

    // Decimals set to 18 by default in ERC20.sol, but you can override if needed
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}