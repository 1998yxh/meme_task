# � SHIB风格Meme代币项目

> 完整的SHIB风格Meme代币智能合约实现，包含税收机制、交易限制、流动性管理等功能

[![Tests](https://img.shields.io/badge/tests-25%20passing-brightgreen)](https://github.com)
[![Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen)](https://github.com)
[![Solidity](https://img.shields.io/badge/solidity-0.8.20-blue)](https://soliditylang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

## ✨ 主要功能

### 🏦 代币税机制
- **智能税收系统**: 买入税 3%、卖出税 5%
- **自动分配**: 流动性税、营销税、销毁税
- **动态税率**: 管理员可调整税率设置
- **税费透明**: 所有税费分配公开透明

### 💧 流动性池集成
- **自动添加流动性**: 收集的代币自动注入 Uniswap 池
- **流动性管理**: 专门的流动性池管理合约
- **奖励机制**: 流动性提供者享受 12% 年化收益
- **灵活提取**: 随时添加或移除流动性

### 🛡️ 交易限制保护
- **金额限制**: 单笔交易和钱包持有量限制
- **频率控制**: 防止高频交易和机器人攻击
- **黑名单系统**: 可禁止恶意地址交易
- **反鲸鱼机制**: 保护小投资者利益

### 🔧 高级功能
- **自动兑换**: 智能兑换机制优化交易体验
- **紧急功能**: 紧急情况下的资金保护
- **权限管理**: 多层级权限控制系统
- **事件日志**: 完整的链上操作记录

## 📁 项目结构

```
meme_task/
├── contracts/              # 智能合约源码
│   ├── shib/
│   │   ├── ShibaInu.sol           # 主代币合约
│   │   └── LiquidityPoolManager.sol # 流动性池管理合约
│   └── pepe/
│       └── pepe.sol               # PEPE 示例合约
├── scripts/                # 部署脚本
│   └── deploy.js                  # 主部署脚本
├── test/                   # 测试文件
│   └── ShibaInu.test.js          # 完整测试套件
├── docs/                   # 文档
│   └── 操作指南.md               # 详细操作指南
├── deployments/            # 部署记录 (自动生成)
├── hardhat.config.js       # Hardhat 配置
├── package.json           # 项目依赖
└── README.md              # 项目说明
```

## 🚀 快速开始

### 环境要求

- Node.js >= 14.0.0
- npm 或 yarn
- Git

### 安装依赖

```bash
# 克隆项目
git clone [repository-url]
cd meme_task

# 安装依赖
npm install
```

### 环境配置

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑 .env 文件，填入实际配置
# - PRIVATE_KEY: 部署账户私钥
# - MAINNET_RPC_URL: 主网 RPC URL
# - ETHERSCAN_API_KEY: 用于合约验证
```

### 编译合约

```bash
npx hardhat compile
```

### 运行测试

```bash
# 运行所有测试
npx hardhat test

# 生成测试覆盖率报告
npx hardhat coverage

# 生成 Gas 使用报告
REPORT_GAS=true npx hardhat test
```

### 部署合约

```bash
# 部署到本地网络
npx hardhat run scripts/deploy.js --network localhost

# 部署到测试网
npx hardhat run scripts/deploy.js --network goerli

# 部署到主网
npx hardhat run scripts/deploy.js --network mainnet
```

## 📋 合约接口

### ShibaInu 主合约

#### 基本信息
```solidity
function name() external view returns (string memory);
function symbol() external view returns (string memory);
function totalSupply() external view returns (uint256);
function balanceOf(address account) external view returns (uint256);
```

#### 税费管理
```solidity
function updateTaxes(uint256 _buyTax, uint256 _sellTax, uint256 _liquidityTax, uint256 _marketingTax, uint256 _burnTax) external;
function getTaxInfo() external view returns (uint256, uint256, uint256, uint256, uint256);
```

#### 交易限制
```solidity
function updateTransactionLimits(uint256 _maxTransactionAmount, uint256 _maxWalletAmount) external;
function updateTransactionCooldown(uint256 _transactionCooldown) external;
function updateBlacklist(address account, bool isBlacklisted) external;
```

#### 流动性管理
```solidity
function setSwapAndLiquifyEnabled(bool _enabled) external;
function updateSwapTokensAtAmount(uint256 _swapTokensAtAmount) external;
```

### LiquidityPoolManager 合约

#### 流动性操作
```solidity
function addLiquidity(uint256 tokenAmount, uint256 tokenAmountMin, uint256 ethAmountMin) external payable;
function removeLiquidity(uint256 lpTokenAmount, uint256 tokenAmountMin, uint256 ethAmountMin) external;
function claimRewards() external;
```

#### 查询功能
```solidity
function getProviderInfo(address provider) external view returns (uint256, uint256, uint256, uint256, uint256, bool);
function calculateRewards(address provider) external view returns (uint256);
function getPoolStats() external view returns (uint256, uint256, uint256, uint256, uint256);
```

## 🎯 使用示例

### 基本代币操作

```javascript
const { ethers } = require("hardhat");

// 连接到已部署的合约
const shibToken = await ethers.getContractAt("ShibaInu", CONTRACT_ADDRESS);

// 启用交易
await shibToken.enableTrading();

// 普通转账
const amount = ethers.utils.parseEther("1000");
await shibToken.transfer(recipientAddress, amount);

// 查询余额
const balance = await shibToken.balanceOf(userAddress);
console.log("余额:", ethers.utils.formatEther(balance));
```

### 流动性管理

```javascript
const poolManager = await ethers.getContractAt("LiquidityPoolManager", POOL_MANAGER_ADDRESS);

// 添加流动性
const tokenAmount = ethers.utils.parseEther("10000");
const ethAmount = ethers.utils.parseEther("1");

await shibToken.approve(poolManager.address, tokenAmount);
await poolManager.addLiquidity(
    tokenAmount,
    tokenAmount.mul(95).div(100), // 5% 滑点保护
    ethAmount.mul(95).div(100),
    { value: ethAmount }
);

// 查询奖励
const rewards = await poolManager.calculateRewards(userAddress);
console.log("待领奖励:", ethers.utils.formatEther(rewards));

// 提取奖励
await poolManager.claimRewards();
```

### 管理员操作

```javascript
// 更新税率
await shibToken.updateTaxes(2, 4, 1, 2, 1); // 买入2%, 卖出4%

// 更新交易限制
await shibToken.updateTransactionLimits(
    ethers.utils.parseEther("5000000"),  // 最大交易额
    ethers.utils.parseEther("20000000")  // 最大钱包额
);

// 黑名单管理
await shibToken.updateBlacklist(maliciousAddress, true);

// 设置免税地址
await shibToken.excludeFromFees(exchangeAddress, true);
```

## 🧪 测试覆盖

项目包含完整的测试套件，覆盖所有主要功能：

- ✅ 合约部署和初始化
- ✅ 基本 ERC20 功能
- ✅ 代币税机制
- ✅ 交易限制功能
- ✅ 流动性池管理
- ✅ 管理员权限控制
- ✅ 边界条件和错误处理
- ✅ 时间相关功能

```bash
# 查看测试结果
npm test

  ShibaInu Token 完整测试
    🏗️ 合约部署测试
      ✓ 应该正确设置代币基本信息
      ✓ 应该将所有代币分配给部署者
      ✓ 应该正确设置钱包地址
      ✓ 应该正确设置初始税率
    💰 基本 ERC20 功能测试
      ✓ 应该支持正常转账
      ✓ 应该支持授权和 transferFrom
    📊 代币税机制测试
      ✓ 普通转账不应收取税费
      ✓ 从交易对购买应收取买入税
      ✓ 卖给交易对应收取卖出税
    ... (更多测试)
```

## 📊 Gas 使用分析

| 操作 | Gas 使用量 | USD 成本 (20 gwei) |
|------|------------|---------------------|
| 部署 ShibaInu | ~3,200,000 | ~$25.60 |
| 部署 PoolManager | ~2,800,000 | ~$22.40 |
| 启用交易 | ~45,000 | ~$0.36 |
| 普通转账 | ~65,000 | ~$0.52 |
| 买入交易 (含税) | ~95,000 | ~$0.76 |
| 卖出交易 (含税) | ~105,000 | ~$0.84 |
| 添加流动性 | ~180,000 | ~$1.44 |

## 🔒 安全特性

### 权限控制
- **Ownable**: 使用 OpenZeppelin 的所有者模式
- **角色分离**: 不同功能具有不同权限级别
- **参数验证**: 所有输入参数都有严格验证

### 攻击防护
- **重入攻击**: 使用 ReentrancyGuard 防护
- **溢出攻击**: 使用 SafeMath 库防护
- **MEV 攻击**: 交易频率和金额限制
- **价格操纵**: 反鲸鱼机制和黑名单系统

### 审计建议
1. 建议进行专业安全审计
2. 逐步发布，先小规模测试
3. 设置合理的初始参数
4. 准备紧急暂停机制

## 🛠️ 开发工具

### 推荐的开发环境
- **VS Code** + Solidity 插件
- **Hardhat** 开发框架
- **Remix** 在线 IDE (用于快速测试)
- **MetaMask** 钱包集成

### 有用的命令

```bash
# 代码格式化
npx prettier --write 'contracts/**/*.sol'

# 安全检查
npx hardhat check

# 生成文档
npx hardhat docgen

# 清理缓存
npx hardhat clean

# 验证合约
npx hardhat verify --network mainnet CONTRACT_ADDRESS "Constructor" "Arguments"
```
