# ♠️ spades ♠️ [![tests](https://github.com/abigger87/spades/actions/workflows/tests.yml/badge.svg)](https://github.com/abigger87/spades/actions/workflows/tests.yml) [![lints](https://github.com/abigger87/spades/actions/workflows/lints.yml/badge.svg)](https://github.com/abigger87/spades/actions/workflows/lints.yml) ![GitHub](https://img.shields.io/github/license/abigger87/spades) ![GitHub package.json version](https://img.shields.io/github/package-json/v/abigger87/spades)

**S**ealed **P**rice **A**ppraisals for **D**eterministic **E**missions.

```m
///       ?????????????????????????????????????? . ######################################      ///
///       ?????????????????????????????????????  %  #####################################      ///
///       ????????????????????????????????????  %*:  ####################################      ///
///       ???????????????????????????????????  %#*?:  ###################################      ///
///       ?????????????????????????????????  ,%##*??:.  #################################      ///
///       ???????????????????????????????  ,%##*?*#*??:.  ###############################      ///
///       ?????????????????????????????  ,%###*??*##*???:.  #############################      ///
///       ???????????????????????????  ,%####*???*###*????:.  ###########################      ///
///       ?????????????????????????  ,%####**????*####**????:.  #########################      ///
///       ???????????????????????  ,%#####**?????*#####**?????:.  #######################      ///
///       ??????????????????????  %######**??????*######**??????:  ######################      ///
///       ?????????????????????  %######**???????*#######**??????:  #####################      ///
///       ????????????????????  %######***???????*#######***??????:  ####################      ///
///       ????????????????????  %######***???????*#######***??????:  ####################      ///
///       ????????????????????  %######***???????*#######***??????:  ####################      ///
///       ?????????????????????  %######**??????***######**??????:  #####################      ///
///       ??????????????????????  '%######****:^%*:^%****??????:'  ######################      ///
///       ????????????????????????   '%####*:'  %*:  '%*????:'   ########################      ///
///       ??????????????????????????           %#*?:           ##########################      ///
///       ?????????????????????????????????  ,%##*??:.  #################################      ///
///       ???????????????????????????????  .%###***???:.  ###############################      ///
///       ??????????????????????????????                   ##############################      ///
///       ???????????????????????????????????????*#######################################      ///
```


## Overview

Current mints sacrifice both price-discovery and gas efficiency for ordering.

This leads to gas wars and bag shilling, often enabled by gated whitelists.

[Spades](https://github.com/abigger87/spades) is an attempt to maximize the ERC721 drop tradeoff by building off of [Cloaks](https://github.com/abigger87/cloaks).


## How it works

Spades is an ERC721 Token with built-in minting broken down into four phases.

#### Phase 1 - Commitments

Spades begins with a commit phase that lasts from `commitStart` to `revealStart`.

During the commit phase, anyone can permissionlessly call the `commit(bytes32)` function, passing in a hashed commitment (32 bytes).

The hashed commitment includes an appraisal price (at which each ERC721 token should be valued) along with a `blindingFactor` that prevents hash table attacks.

Calling the commitment also requires a `depositAmount` of ether or the `depositToken` to prevent commitment spam.

#### Phase 2 - Reveals

At this point, there are a bunch of commitments stored in the Spades Contract.

Once the Reveal Phase begins when the `block.timestamp` reaches `revealStart`, participants from phase 1 can reveal their appraisal by calling the `reveal(uint256,bytes32)` function.

Where the first argument is the appraisal value and the second is the `blindingFactor`.

Once this function is called, the sender's sealed appraisal becomes public.

⚠️ NOTE ⚠️  If a commit phase participant fails to reveal their commitment, they will incur the Spade's `MAX_LOSS_PENALTY` (in bips) on their deposit. After the reveal phase, the user may call `lostReveal()` to extract the remainder of their deposit.

#### Phase 3 - Restricted Mint

Now that all appraisals have been revealed, a 




The initial lbp price for the restricted mint period is calculated as the mean of the revealed commitments.

Where a participant's discount to the public mint price during the restricted mint is inversly proportional to how close their appraisal was to the mean. 




#### ....


Mints suck...

They're difficult to mint, oft impossible.
The mint price is fixed - artists and creators don't realize upside.

Is this fixable?

The answer: not without tradeoffs.

To satisfy this, spades sacrifices ordering (first-come first-serve) for price-discovery and gas efficiency.

_How_ does this work?

spades start with a commit phase, that lasts for an arbitrarily long period to prevent gas wars.
During the commit phase, anyone can call `commit()`, providing a sealed bid price (appraisal) and sending `depositAmount` of a token to the Cloak.

This is possible by using a commitment scheme where the sealed value is hashed and revealed in the next phase.
Read more on commitment schemes [here](https://medium.com/swlh/exploring-commit-reveal-schemes-on-ethereum-c4ff5a777db8). 

Once the commit phase ends, everyone who commited values then calls `reveal()`, providing the bid price. Once this function is called, the sender's sealed bid is becomes public.

NOTE: Commitments can only be made during the commit phase.

Once the reveal phase ends, Cloak enters the third and last phase - the mint phase.

At this time, the mint price is determined by taking the mean of all the revealed bids. The final mint price is the max of either this calculated price or the `minPrice` set by the Cloak creator.

To incentivize bid accuracy, only bids that are in the range of [`resultPrice - flex * stdDev`, `resultPrice + flex * stdDev`], where `flex` is a scalar value set by the Cloak creator.

Anyone who isn't in this range can call `forgo()` to withdraw their deposit token.

If a user ends up in the range and forgos, they suffer a loss penalty proportional to how close they are to the resulting price.
Additionally, if a bid is an outlier, a loss penalty is incurred proportional to a Z-Score.

NOTE: If a commitooor forgets to reveal their sealed bid, they can call `lostReveal()` to withdraw their deposit.

## Extremely Technical Docs

![spade](./assets/spades.jpeg)



## Blueprint

```ml
lib
├─ ds-test — https://github.com/dapphub/ds-test
├─ forge-std — https://github.com/brockelmore/forge-std
├─ solmate — https://github.com/Rari-Capital/solmate
├─ clones-with-immutable-args — https://github.com/wighawag/clones-with-immutable-args
src
├─ tests
│  └─ Spade.t — "Spade Tests"
└─ Spade — "Spade ERC721 Contract"
```

## Development

A [Spade](https://github.com/abigger87/spades) is an extensible ERC721 implementation with a commit-reveal scheme and lbp built _into_ the ERC721 contract itself.
The only contract is located in [src/](./src/) called [Spade](./src/Spade.sol).

Both [DappTools](https://dapp.tools/) and [Foundry](https://github.com/gaskonst/foundry) are supported. Installation instructions for both are included below.

#### Install DappTools

Install DappTools using their [installation guide](https://github.com/dapphub/dapptools#installation).

#### First time with Forge/Foundry?

See the official Foundry installation [instructions](https://github.com/gakonst/foundry/blob/master/README.md#installation).

Don't have [rust](https://www.rust-lang.org/tools/install) installed?
Run
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Then, install the [foundry](https://github.com/gakonst/foundry) toolchain installer (`foundryup`) with:
```bash
curl -L https://foundry.paradigm.xyz | bash
```

Now that you've installed the `foundryup` binary,
anytime you need to get the latest `forge` or `cast` binaries,
you can run `foundryup`.

So, simply execute:
```bash
foundryup
```

🎉 Foundry is installed! 🎉

#### Setup

```bash
make
# OR #
make setup
```

#### Build

```bash
make build
```

#### Run Tests

```bash
make test
```

#### Configure Foundry

Using [foundry.toml](./foundry.toml), Foundry is easily configurable.

## License

[AGPL-3.0-only](https://github.com/abigger87/spades/blob/master/LICENSE)

# Acknowledgements

- [Glass.xyz's LBP ERC721](https://github.com/GlassProtocol/LBPERC721/blob/main/src/LBPERC721.sol)
- [commit-reveal schemes](https://medium.com/swlh/exploring-commit-reveal-schemes-on-ethereum-c4ff5a777db8)
- [foundry](https://github.com/gakonst/foundry)
- [solmate](https://github.com/Rari-Capital/solmate)
- [forge-std](https://github.com/brockelmore/forge-std)
- [clones-with-immutable-args](https://github.com/wighawag/clones-with-immutable-args).
- [foundry-toolchain](https://github.com/onbjerg/foundry-toolchain) by [onbjerg](https://github.com/onbjerg).
- [forge-template](https://github.com/FrankieIsLost/forge-template) by [FrankieIsLost](https://github.com/FrankieIsLost).
- [Georgios Konstantopoulos](https://github.com/gakonst) for [forge-template](https://github.com/gakonst/forge-template) resource.

## Disclaimer

_These smart contracts are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the user interface or the smart contracts. They have not been audited and as such there can be no assurance they will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk._
