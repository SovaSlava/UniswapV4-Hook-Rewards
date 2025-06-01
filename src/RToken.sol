// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;


import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
contract RToken is ERC20, Owned {
    constructor(string memory _name, string memory _symbol, address newOwner) 
        ERC20(_name, _symbol, 18)
        Owned(newOwner) {}


    error onlyMinterOrOwner();
    address public minter;

    function mint(address to, uint256 value) external {
        if(msg.sender != minter && msg.sender != owner) revert onlyMinterOrOwner();
        _mint(to, value);
    } 

    function setMinter(address newMinter) external onlyOwner {
        minter = newMinter;
    }
}