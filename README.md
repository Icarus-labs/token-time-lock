# 矿业生态聚合智能合约

## 部署

简单的部署直接参考`scripts/sample-scripts`

## contracts/MiningEco.sol

合约平台的主要逻辑实现。目前的设计只含有对项目创建的管理和初期的项目投资。合约本身采用的是 openzepplin 的~代理升级模式~，为日后的平台升级留有余地。

主要的交互：

- `function new_project(uint256 template_id, bytes32 project_id, uint256 max_amount, string symbol, bytes init_calldata)` 参数都很直白，遵守相应的数据类型即可。说明最后一个 init_calldata，这是用来初始化调用被创建的项目合约的 calldata。由平台创建的项目合约都实现了 initialize 方法。不同的项目模板，可以允许实现不同函数参数签名的 initialize 方法。所以这里利用 bytes 这种完全的灵活性来保证项目合约的初始化不受到局限。

- `function invest(bytes32 project_id, uint256 amount)`
  被初始化后的项目，按照初始化设置的时间窗口，允许投资者进行投资。
