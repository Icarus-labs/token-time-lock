# 智能合约：ETH交换ERC20 token

火币测试网合约地址：

- SwapImpl地址: [0x710d68647b13b932cF4883b5Ca8B0E694230936c](https://testnet.hecoinfo.com/address/0x710d68647b13b932cf4883b5ca8b0e694230936c)
- dht地址: [0x1104329330762D18a359bB9ED25b2520a7E01242](https://testnet.hecoinfo.com/address/0x1104329330762d18a359bb9ed25b2520a7e01242)

## 测试

确保先自行启动了`npx hardhat node`

```sh
npx hardhat test test/SwapImpl.test.js --newwork localhost
```

## 部署

```sh
npx hardhat run --network huobi_testnet scripts/swap-deploy.js
```

## 开发

开发环境基于[hardhat](https://hardhat.org)

#### SwapImpl.sol

该合约实现ETH和ERC20 token按比例互换。

主要部署参数：

- `_id`

  交易对ID

- `_symbol`

  交易对标识符

- `_ratio`

  交换比例

- `_token`

  ERC20 token地址
