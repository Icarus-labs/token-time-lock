# 矿业生态聚合智能合约

主网合约地址：

- DADA: [0x54559aD7Ec464af2FC360B9405412eC8bB0F48Ed](https://etherscan.io/address/0x54559aD7Ec464af2FC360B9405412eC8bB0F48Ed)
- USDT: [0xdAC17F958D2ee523a2206206994597C13D831ec7](https://etherscan.io/address/0xdAC17F958D2ee523a2206206994597C13D831ec7)
- MiningEcoProxy: [0xA47605cfdB95E2D3487375b896F55904af3cfD62](https://etherscan.io/address/0xA47605cfdB95E2D3487375b896F55904af3cfD62)



## 测试

确保先自行启动了`npx hardhat node`

```sh
npm test [-- test/xxxxx.js]
```

测试脚本在测试开始之前将合约内的`BLOCKS_PER_DAY`改成 10，方便快速测试合约状态变化。目前所有的测试脚本也都是基于`BLOCKS_PER_DAY = 10`来编写的。

可以直接参考[test.sh](./test.sh)



## 部署

简单的部署直接参考`scripts/sample-scripts`。可以手工部署，也可以写脚本具体看需求。虽然[OpenZeppelin](https://blog.openzeppelin.com/guides/)官方有提供一个`Proxy Deploy`相关的范式，但是我测试下来似乎不够灵活，目前我也没有想到更好的方式。

目前的平台框架基本已经确定了，所以部署主要有两种，因为合约开发的特性这两种部署类型我们采用的不同的部署方式，具体在开发环节会详细阐述：

- MiningEco合约更新
- 更新/增加项目模板

目前所有的合约部署，基本上都是通过[DaDa Deployer](https://etherscan.io/address/0x92E73408801e713f8371f8A8c31a40130ae61a40)来执行交易。



## 开发

开发环境基于[hardhat](https://hardhat.org)

#### MiningEco.sol

合约平台的主要逻辑实现。目前的设计只含有对项目创建的管理和初期的项目投资。合约本身采用的是 openzepplin 的~代理升级模式~，为日后的平台升级留有余地。

可以从这个链接了解合约升级的各种模型: [Proxy Patterns](https://blog.openzeppelin.com/proxy-patterns/)

主要的交互：

- `function initialize(address token, address usdt, address payable _insurance_vault, address payable _fee_vault)` 

  因为采用了proxy模式，不允许用constructor初始化合约，所以部署MiningEco.sol后，利用initialize方法进行合约的初始化工作。目前已经部署完成，所以这个方法大概率不太会再被调用。

- `function new_project(uint256 template_id, bytes32 project_id, uint256 max_amount, string symbol, bytes init_calldata)` 

  参数都很直白，遵守相应的数据类型即可。说明最后一个 init_calldata，这是用来初始化调用被创建的项目合约的 calldata。由平台创建的项目合约都实现了 initialize 方法。不同的项目模板，可以允许实现不同函数参数签名的 initialize 方法。所以这里利用 bytes 这种完全的灵活性来保证项目合约的初始化不受到局限。

- `function invest(bytes32 project_id, uint256 amount)`
  被初始化后的项目，按照初始化设置的时间窗口，允许投资者进行投资。
  
- `function insurance(bytes32 project_id) returns (uint256) `

  返回项目当前需要支付的保险金数额

- `function project_status(bytes32 project_id) returns (uint256)`

  返回项目当前状态，对template的`function status()`的简单wrapper。

- `function pay_insurance(bytes32 project_id)`

  项目经历通过发送pay_insurance交易来支付项目保险金。在需要的时候，pay_insurance交易需要前置一个approve交易。

- `function transfer_token(address token_address, uint256 amount, address to_account)`

  被管理委员会管理的方法，用来从MiningEco转移多余的token。

- `function set_template(uint256 i, address projectTemplate)`

  各种类型的项目都是根据已经部署的相应的项目模板动态生成的新合约。MiningEco只记录template id 和 工厂合约的地址。由前端选择要创建的项目合约模板类型。

- `function audit_project(bytes32 project_id, bool yn, uint256 _insurance_rate)`

  审核项目的接口，bool值表示同意或者拒绝true/false，_insurance_rate是审核通过的时候可以由审核人override一次保证金率。
