# Uniswap v4 Hook -  Rewardin liquidity providers for ERC20-tokens 🦄
### **The hook supports flexible reward settings**

Created based on a template [`v4-template`](https://github.com/uniswapfoundation/v4-template/generate)

### Description

The hook is designed to reward liquidity providers with ERC20 tokens. The reward is calculated when they withdraw liquidity in full or in part.

When the LP provides liquidity, the hook records the amount and the current time. Later, when liquidity is withdrawn, the reward is calculated based on this data and the hook accesses the token contract, calling the mint and mintit functions of the token to the user's address, or to another address that the user can specify.

### Key Features

* Setting an individual multiplier for each user
* Support for increasing liquidity and partial withdrawal of liquidity
* Ability to set a minimum threshold of accumulated liquidity, reaching which the user will be rewarded
* Ability to set the rate for calculating the reward. Moreover, the rate is saved in the user structure, so the user can be sure that the rate for him will not change
* The hook will notify about the problem when minting the reward token (if this happens) through the event - CantMintReward

Hook has tests in test folder.
---

### Check Forge Installation
*Ensure that you have correctly installed Foundry (Forge) Stable. You can update Foundry by running:*

```
foundryup
```

> *v4-template* appears to be _incompatible_ with Foundry Nightly. See [foundry announcements](https://book.getfoundry.sh/announcements) to revert back to the stable build



## Set up

*requires [foundry](https://book.getfoundry.sh)*

```
forge install
forge test
```

### Local Development (Anvil)

Other than writing unit tests (recommended!), you can only deploy & test hooks on [anvil](https://book.getfoundry.sh/anvil/)

```bash
# start anvil, a local EVM chain
anvil

# in a new terminal
forge script script/Anvil.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast
```

See [script/](script/) for hook deployment, pool creation, liquidity provision, and swapping.

---

<details>
<summary><h2>Troubleshooting</h2></summary>



### *Permission Denied*

When installing dependencies with `forge install`, Github may throw a `Permission Denied` error

Typically caused by missing Github SSH keys, and can be resolved by following the steps [here](https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh) 

Or [adding the keys to your ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent), if you have already uploaded SSH keys

### Anvil fork test failures

Some versions of Foundry may limit contract code size to ~25kb, which could prevent local tests to fail. You can resolve this by setting the `code-size-limit` flag

```
anvil --code-size-limit 40000
```

### Hook deployment failures

Hook deployment failures are caused by incorrect flags or incorrect salt mining

1. Verify the flags are in agreement:
    * `getHookCalls()` returns the correct flags
    * `flags` provided to `HookMiner.find(...)`
2. Verify salt mining is correct:
    * In **forge test**: the *deployer* for: `new Hook{salt: salt}(...)` and `HookMiner.find(deployer, ...)` are the same. This will be `address(this)`. If using `vm.prank`, the deployer will be the pranking address
    * In **forge script**: the deployer must be the CREATE2 Proxy: `0x4e59b44847b379578588920cA78FbF26c0B4956C`
        * If anvil does not have the CREATE2 deployer, your foundry may be out of date. You can update it with `foundryup`

</details>

---

Additional resources:

[Uniswap v4 docs](https://docs.uniswap.org/contracts/v4/overview)

[v4-periphery](https://github.com/uniswap/v4-periphery) contains advanced hook implementations that serve as a great reference

[v4-core](https://github.com/uniswap/v4-core)

[v4-by-example](https://v4-by-example.org)

