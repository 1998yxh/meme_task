// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ShibaInu Token
 * @dev SHIB 风格的 Meme 代币合约，包含代币税、流动性池集成和交易限制功能
 * @author Meme Token Development Team
 */
contract ShibaInu is ERC20, Ownable, ReentrancyGuard {

    // ============ 状态变量 ============

    // 代币税相关变量
    uint256 public buyTax = 3;              // 买入税 3%
    uint256 public sellTax = 5;             // 卖出税 5%
    uint256 public liquidityTax = 2;        // 流动性税 2%
    uint256 public marketingTax = 2;        // 营销税 2%
    uint256 public burnTax = 1;             // 销毁税 1%
    
    // 税费分配地址
    address public liquidityWallet;         // 流动性钱包
    address public marketingWallet;         // 营销钱包
    address public deadWallet = 0x000000000000000000000000000000000000dEaD; // 销毁地址
    
    // Uniswap 集成
    address public uniswapV2Router;         // Uniswap V2 路由器地址
    address public uniswapV2Pair;           // Uniswap V2 交易对地址
    
    // 交易限制变量
    bool public tradingEnabled = false;     // 交易开关
    uint256 public maxTransactionAmount;    // 单笔交易最大额度
    uint256 public maxWalletAmount;         // 钱包最大持有量
    uint256 public swapTokensAtAmount;      // 自动兑换阈值
    
    // 交易频率限制
    mapping(address => uint256) public lastTransactionTime;  // 最后交易时间
    uint256 public transactionCooldown = 30;                // 交易冷却时间（秒）
    
    // 每日交易限制
    mapping(address => uint256) public dailyTransactionCount;   // 每日交易次数
    mapping(address => uint256) public lastTransactionDay;     // 最后交易日期
    uint256 public maxDailyTransactions = 10;                  // 每日最大交易次数
    
    // 免税和免限制地址
    mapping(address => bool) public isExcludedFromFees;     // 免税地址
    mapping(address => bool) public isExcludedFromLimits;   // 免限制地址
    mapping(address => bool) public blacklist;             // 黑名单地址
    
    // 自动流动性相关
    bool private inSwapAndLiquify;          // 防止递归调用
    bool public swapAndLiquifyEnabled = true; // 自动添加流动性开关
    
    // ============ 事件定义 ============
    
    event TradingEnabled();
    event TaxesUpdated(uint256 buyTax, uint256 sellTax);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiquidity);
    event TransactionLimitUpdated(uint256 maxTransactionAmount, uint256 maxWalletAmount);
    event BlacklistUpdated(address indexed account, bool isBlacklisted);
    event TaxWalletsUpdated(address liquidityWallet, address marketingWallet);
    
    // ============ 修饰符 ============
    
    /**
     * @dev 防止在兑换流动性过程中重入
     */
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    
    /**
     * @dev 检查交易频率限制
     */
    modifier rateLimited(address user) {
        if (!isExcludedFromLimits[user]) {
            require(
                block.timestamp >= lastTransactionTime[user] + transactionCooldown,
                "Transaction too frequent"
            );
            lastTransactionTime[user] = block.timestamp;
            
            // 检查每日交易次数
            uint256 currentDay = block.timestamp / 1 days;
            if (lastTransactionDay[user] != currentDay) {
                dailyTransactionCount[user] = 0;
                lastTransactionDay[user] = currentDay;
            }
            
            require(
                dailyTransactionCount[user] < maxDailyTransactions,
                "Daily transaction limit exceeded"
            );
            dailyTransactionCount[user] = dailyTransactionCount[user] + 1;
        }
        _;
    }
    
    // ============ 构造函数 ============
    
    /**
     * @dev 合约构造函数
     * @param _name 代币名称
     * @param _symbol 代币符号
     * @param _totalSupply 总供应量
     * @param _uniswapV2Router Uniswap V2 路由器地址
     * @param _liquidityWallet 流动性钱包地址
     * @param _marketingWallet 营销钱包地址
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        address _uniswapV2Router,
        address _liquidityWallet,
        address _marketingWallet
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        // 设置总供应量并铸造给合约部署者
        _mint(msg.sender, _totalSupply);
        
        // 设置 Uniswap 路由器
        uniswapV2Router = _uniswapV2Router;
        
        // 设置税费钱包
        liquidityWallet = _liquidityWallet;
        marketingWallet = _marketingWallet;
        
        // 设置交易限制（总供应量的1%作为单笔限制，2%作为钱包限制）
        maxTransactionAmount = _totalSupply * 1 / 100;
        maxWalletAmount = _totalSupply * 2 / 100;
        swapTokensAtAmount = _totalSupply * 5 / 10000; // 0.05%
        
        // 排除特定地址的费用和限制
        isExcludedFromFees[owner()] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[liquidityWallet] = true;
        isExcludedFromFees[marketingWallet] = true;
        
        isExcludedFromLimits[owner()] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[liquidityWallet] = true;
        isExcludedFromLimits[marketingWallet] = true;
    }
    
    // ============ 接收 ETH ============
    
    receive() external payable {}
    
    // ============ 核心转账函数 ============
    
    /**
     * @dev 重写转账函数，添加税费和限制逻辑
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(to != address(0), "ERC20: transfer to the zero address");
        
        // 允许铸造（from == address(0)）和销毁（to == address(0)）
        if (from != address(0) && to != address(0)) {
            require(!blacklist[from] && !blacklist[to], "Blacklisted address");
            require(amount > 0, "Transfer amount must be greater than zero");
            
            // 检查交易是否已启用
            if (!tradingEnabled) {
                require(
                    isExcludedFromLimits[from] || isExcludedFromLimits[to],
                    "Trading not yet enabled"
                );
            }
            
            // 检查交易限制
            if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
                require(amount <= maxTransactionAmount, "Transfer amount exceeds the maxTransactionAmount");
                
                // 检查接收方钱包持有量限制（除了卖给交易对的情况）
                if (to != uniswapV2Pair) {
                    require(
                        balanceOf(to) + amount <= maxWalletAmount,
                        "Exceeds maximum wallet token amount"
                    );
                }
            }
            
            // 检查是否需要收取税费
            bool takeFee = false;
            
            // 只有买入或卖出交易才收取费用
            if (from == uniswapV2Pair || to == uniswapV2Pair) {
                takeFee = true;
            }
            
            // 如果发送方或接收方被排除在费用之外，则不收取费用
            if (isExcludedFromFees[from] || isExcludedFromFees[to]) {
                takeFee = false;
            }
            
            // 执行转账和税费计算
            if (takeFee) {
                uint256 totalTaxes = 0;
                
                // 买入交易（从交易对买入）
                if (from == uniswapV2Pair) {
                    totalTaxes = buyTax;
                }
                // 卖出交易（卖给交易对）
                else if (to == uniswapV2Pair) {
                    totalTaxes = sellTax;
                }
                
                // 计算税费金额
                uint256 taxAmount = amount * totalTaxes / 100;
                uint256 transferAmount = amount - taxAmount;
                
                // 执行转账
                super._update(from, to, transferAmount);
                
                // 收取税费到合约地址
                if (taxAmount > 0) {
                    super._update(from, address(this), taxAmount);
                }
                return;
            }
        }
        
        // 不收取费用的直接转账（包括铸造和销毁）
        super._update(from, to, amount);
    }
    
    // ============ 管理员功能 ============
    
    /**
     * @dev 启用交易
     */
    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "Trading already enabled");
        tradingEnabled = true;
        emit TradingEnabled();
    }
    
    /**
     * @dev 设置 Uniswap 交易对地址
     */
    function setUniswapV2Pair(address _uniswapV2Pair) external onlyOwner {
        uniswapV2Pair = _uniswapV2Pair;
    }
    
    /**
     * @dev 更新税率
     */
    function updateTaxes(
        uint256 _buyTax,
        uint256 _sellTax,
        uint256 _liquidityTax,
        uint256 _marketingTax,
        uint256 _burnTax
    ) external onlyOwner {
        require(_buyTax <= 10, "Buy tax too high");
        require(_sellTax <= 15, "Sell tax too high");
        require(_liquidityTax + _marketingTax + _burnTax <= 10, "Total tax distribution too high");
        
        buyTax = _buyTax;
        sellTax = _sellTax;
        liquidityTax = _liquidityTax;
        marketingTax = _marketingTax;
        burnTax = _burnTax;
        
        emit TaxesUpdated(_buyTax, _sellTax);
    }
    
    /**
     * @dev 更新交易限制
     */
    function updateTransactionLimits(
        uint256 _maxTransactionAmount,
        uint256 _maxWalletAmount
    ) external onlyOwner {
        require(_maxTransactionAmount >= totalSupply() * 1 / 1000, "Max transaction too low"); // 最少0.1%
        require(_maxWalletAmount >= totalSupply() * 5 / 1000, "Max wallet too low"); // 最少0.5%
        
        maxTransactionAmount = _maxTransactionAmount;
        maxWalletAmount = _maxWalletAmount;
        
        emit TransactionLimitUpdated(_maxTransactionAmount, _maxWalletAmount);
    }
    
    /**
     * @dev 更新交易频率限制
     */
    function updateTransactionCooldown(uint256 _transactionCooldown) external onlyOwner {
        require(_transactionCooldown <= 300, "Cooldown too long"); // 最多5分钟
        transactionCooldown = _transactionCooldown;
    }
    
    /**
     * @dev 更新每日交易次数限制
     */
    function updateMaxDailyTransactions(uint256 _maxDailyTransactions) external onlyOwner {
        require(_maxDailyTransactions >= 5, "Daily transactions too low");
        maxDailyTransactions = _maxDailyTransactions;
    }
    
    /**
     * @dev 更新税费钱包地址
     */
    function updateTaxWallets(
        address _liquidityWallet,
        address _marketingWallet
    ) external onlyOwner {
        require(_liquidityWallet != address(0), "Liquidity wallet cannot be zero address");
        require(_marketingWallet != address(0), "Marketing wallet cannot be zero address");
        
        liquidityWallet = _liquidityWallet;
        marketingWallet = _marketingWallet;
        
        emit TaxWalletsUpdated(_liquidityWallet, _marketingWallet);
    }
    
    /**
     * @dev 设置免税地址
     */
    function excludeFromFees(address account, bool excluded) external onlyOwner {
        isExcludedFromFees[account] = excluded;
    }
    
    /**
     * @dev 设置免限制地址
     */
    function excludeFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
    }
    
    /**
     * @dev 黑名单管理
     */
    function updateBlacklist(address account, bool isBlacklisted) external onlyOwner {
        blacklist[account] = isBlacklisted;
        emit BlacklistUpdated(account, isBlacklisted);
    }
    
    /**
     * @dev 设置自动兑换阈值
     */
    function updateSwapTokensAtAmount(uint256 _swapTokensAtAmount) external onlyOwner {
        require(_swapTokensAtAmount >= totalSupply() * 1 / 100000, "Swap amount too low"); // 最少0.001%
        swapTokensAtAmount = _swapTokensAtAmount;
    }
    
    /**
     * @dev 切换自动添加流动性功能
     */
    function setSwapAndLiquifyEnabled(bool _enabled) external onlyOwner {
        swapAndLiquifyEnabled = _enabled;
    }
    
    // ============ 紧急功能 ============
    
    /**
     * @dev 紧急提取合约中的 ETH
     */
    function emergencyWithdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "ETH withdrawal failed");
    }
    
    /**
     * @dev 紧急提取合约中的代币
     */
    function emergencyWithdrawTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(this), "Cannot withdraw own tokens");
        IERC20(token).transfer(owner(), amount);
    }
    
    // ============ 查询功能 ============
    
    /**
     * @dev 获取账户的交易统计信息
     */
    function getAccountStats(address account) external view returns (
        uint256 balance,
        uint256 lastTransactionTime_,
        uint256 dailyTransactionCount_,
        bool isExcludedFromFees_,
        bool isExcludedFromLimits_,
        bool isBlacklisted
    ) {
        return (
            balanceOf(account),
            lastTransactionTime[account],
            dailyTransactionCount[account],
            isExcludedFromFees[account],
            isExcludedFromLimits[account],
            blacklist[account]
        );
    }
    
    /**
     * @dev 获取当前税率设置
     */
    function getTaxInfo() external view returns (
        uint256 buyTax_,
        uint256 sellTax_,
        uint256 liquidityTax_,
        uint256 marketingTax_,
        uint256 burnTax_
    ) {
        return (buyTax, sellTax, liquidityTax, marketingTax, burnTax);
    }
    
    /**
     * @dev 获取交易限制信息
     */
    function getLimitsInfo() external view returns (
        uint256 maxTransactionAmount_,
        uint256 maxWalletAmount_,
        uint256 transactionCooldown_,
        uint256 maxDailyTransactions_,
        bool tradingEnabled_
    ) {
        return (
            maxTransactionAmount,
            maxWalletAmount,
            transactionCooldown,
            maxDailyTransactions,
            tradingEnabled
        );
    }
}

// ============ Uniswap 接口 ============

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    
    function WETH() external pure returns (address);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}