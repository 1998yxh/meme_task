// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LiquidityPoolManager
 * @dev 流动性池管理合约，提供添加和移除流动性的功能
 * @author Meme Token Development Team
 */
contract LiquidityPoolManager is Ownable, ReentrancyGuard {

    // ============ 状态变量 ============
    
    IERC20 public immutable token;              // 代币合约地址
    address public immutable router;            // Uniswap V2 路由器
    address public immutable pair;              // 交易对地址
    
    // 流动性提供者信息
    struct LiquidityProvider {
        uint256 tokenAmount;        // 提供的代币数量
        uint256 ethAmount;          // 提供的 ETH 数量
        uint256 lpTokens;           // 获得的 LP 代币数量
        uint256 addTime;            // 添加时间
        uint256 lastClaimTime;      // 最后提取奖励时间
        bool isActive;              // 是否活跃
    }
    
    mapping(address => LiquidityProvider) public liquidityProviders;
    address[] public providerList;
    
    // 奖励机制
    uint256 public totalRewardsDistributed;    // 已分发奖励总额
    uint256 public rewardRate = 12;            // 年化奖励率 (12%)
    uint256 public constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60;
    
    // 流动性池统计
    uint256 public totalTokensInPool;          // 池中总代币数量
    uint256 public totalETHInPool;             // 池中总 ETH 数量
    uint256 public totalProviders;             // 总提供者数量
    
    // 费用设置
    uint256 public addLiquidityFee = 50;       // 添加流动性手续费 (0.5%)
    uint256 public removeLiquidityFee = 100;   // 移除流动性手续费 (1%)
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    // ============ 事件定义 ============
    
    event LiquidityAdded(
        address indexed provider,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 lpTokens
    );
    
    event LiquidityRemoved(
        address indexed provider,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 lpTokens
    );
    
    event RewardsClaimed(address indexed provider, uint256 amount);
    event FeesUpdated(uint256 addFee, uint256 removeFee);
    event RewardRateUpdated(uint256 newRate);
    
    // ============ 修饰符 ============
    
    modifier validProvider() {
        require(liquidityProviders[msg.sender].isActive, "Not an active liquidity provider");
        _;
    }
    
    modifier validAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than zero");
        _;
    }
    
    // ============ 构造函数 ============
    
    /**
     * @dev 构造函数
     * @param _token 代币合约地址
     * @param _router Uniswap V2 路由器地址
     * @param _pair 交易对地址
     */
    constructor(
        address _token,
        address _router,
        address _pair
    ) Ownable(msg.sender) {
        require(_token != address(0), "Token address cannot be zero");
        require(_router != address(0), "Router address cannot be zero");
        require(_pair != address(0), "Pair address cannot be zero");
        
        token = IERC20(_token);
        router = _router;
        pair = _pair;
    }
    
    // ============ 流动性管理功能 ============
    
    /**
     * @dev 添加流动性（简化版本）
     * @param tokenAmount 要添加的代币数量
     */
    function addLiquidity(
        uint256 tokenAmount
    ) external payable nonReentrant validAmount(tokenAmount) validAmount(msg.value) {
        require(msg.value > 0, "Must send ETH");
        
        // 计算手续费
        uint256 fee = tokenAmount * addLiquidityFee / FEE_DENOMINATOR;
        uint256 actualTokenAmount = tokenAmount - fee;
        
        // 转移代币到合约
        require(
            token.transferFrom(msg.sender, address(this), tokenAmount),
            "Token transfer failed"
        );
        
        // 如果是新的流动性提供者，添加到列表
        if (!liquidityProviders[msg.sender].isActive) {
            providerList.push(msg.sender);
            totalProviders = totalProviders + 1;
            liquidityProviders[msg.sender].isActive = true;
            liquidityProviders[msg.sender].addTime = block.timestamp;
            liquidityProviders[msg.sender].lastClaimTime = block.timestamp;
        }
        
        // 更新提供者信息（简化版本，不实际调用 Uniswap）
        liquidityProviders[msg.sender].tokenAmount = liquidityProviders[msg.sender].tokenAmount + actualTokenAmount;
        liquidityProviders[msg.sender].ethAmount = liquidityProviders[msg.sender].ethAmount + msg.value;
        liquidityProviders[msg.sender].lpTokens = liquidityProviders[msg.sender].lpTokens + actualTokenAmount; // 简化计算
        
        // 更新池统计
        totalTokensInPool = totalTokensInPool + actualTokenAmount;
        totalETHInPool = totalETHInPool + msg.value;
        
        emit LiquidityAdded(msg.sender, actualTokenAmount, msg.value, actualTokenAmount);
    }
    
    /**
     * @dev 移除流动性（简化版本）
     * @param lpTokenAmount 要移除的 LP 代币数量
     */
    function removeLiquidity(
        uint256 lpTokenAmount
    ) external nonReentrant validProvider validAmount(lpTokenAmount) {
        require(
            liquidityProviders[msg.sender].lpTokens >= lpTokenAmount,
            "Insufficient LP tokens"
        );
        
        // 计算按比例返还的代币和 ETH
        uint256 tokenAmount = liquidityProviders[msg.sender].tokenAmount * lpTokenAmount / liquidityProviders[msg.sender].lpTokens;
        uint256 ethAmount = liquidityProviders[msg.sender].ethAmount * lpTokenAmount / liquidityProviders[msg.sender].lpTokens;
        
        // 计算手续费
        uint256 tokenFee = tokenAmount * removeLiquidityFee / FEE_DENOMINATOR;
        uint256 ethFee = ethAmount * removeLiquidityFee / FEE_DENOMINATOR;
        
        uint256 actualTokenAmount = tokenAmount - tokenFee;
        uint256 actualETHAmount = ethAmount - ethFee;
        
        // 更新提供者信息
        liquidityProviders[msg.sender].tokenAmount = liquidityProviders[msg.sender].tokenAmount - tokenAmount;
        liquidityProviders[msg.sender].ethAmount = liquidityProviders[msg.sender].ethAmount - ethAmount;
        liquidityProviders[msg.sender].lpTokens = liquidityProviders[msg.sender].lpTokens - lpTokenAmount;
        
        // 如果提供者的 LP 代币为 0，标记为非活跃
        if (liquidityProviders[msg.sender].lpTokens == 0) {
            liquidityProviders[msg.sender].isActive = false;
            totalProviders = totalProviders - 1;
        }
        
        // 更新池统计
        totalTokensInPool = totalTokensInPool - tokenAmount;
        totalETHInPool = totalETHInPool - ethAmount;
        
        // 转移代币和 ETH 给用户
        require(token.transfer(msg.sender, actualTokenAmount), "Token transfer failed");
        payable(msg.sender).transfer(actualETHAmount);
        
        emit LiquidityRemoved(msg.sender, actualTokenAmount, actualETHAmount, lpTokenAmount);
    }
    
    // ============ 奖励机制 ============
    
    /**
     * @dev 计算可提取的奖励
     * @param provider 流动性提供者地址
     */
    function calculateRewards(address provider) public view returns (uint256) {
        if (!liquidityProviders[provider].isActive) {
            return 0;
        }
        
        LiquidityProvider memory providerInfo = liquidityProviders[provider];
        uint256 timeStaked = block.timestamp - providerInfo.lastClaimTime;
        uint256 lpBalance = providerInfo.lpTokens;
        
        // 计算年化奖励
        uint256 annualReward = lpBalance * rewardRate / 100;
        uint256 timeBasedReward = annualReward * timeStaked / SECONDS_PER_YEAR;
        
        return timeBasedReward;
    }
    
    /**
     * @dev 提取奖励
     */
    function claimRewards() external nonReentrant validProvider {
        uint256 rewards = calculateRewards(msg.sender);
        require(rewards > 0, "No rewards available");
        
        // 更新最后提取时间
        liquidityProviders[msg.sender].lastClaimTime = block.timestamp;
        totalRewardsDistributed = totalRewardsDistributed + rewards;
        
        // 发放奖励（这里使用代币作为奖励）
        require(token.transfer(msg.sender, rewards), "Reward transfer failed");
        
        emit RewardsClaimed(msg.sender, rewards);
    }
    
    // ============ 查询功能 ============
    
    /**
     * @dev 获取流动性提供者信息
     * @param provider 提供者地址
     */
    function getProviderInfo(address provider) external view returns (
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 lpTokens,
        uint256 addTime,
        uint256 pendingRewards,
        bool isActive
    ) {
        LiquidityProvider memory info = liquidityProviders[provider];
        return (
            info.tokenAmount,
            info.ethAmount,
            info.lpTokens,
            info.addTime,
            calculateRewards(provider),
            info.isActive
        );
    }
    
    /**
     * @dev 获取池统计信息
     */
    function getPoolStats() external view returns (
        uint256 totalTokens,
        uint256 totalETH,
        uint256 totalProviders_,
        uint256 totalRewards,
        uint256 currentRewardRate
    ) {
        return (
            totalTokensInPool,
            totalETHInPool,
            totalProviders,
            totalRewardsDistributed,
            rewardRate
        );
    }
    
    // ============ 管理员功能 ============
    
    /**
     * @dev 更新费用设置
     */
    function updateFees(uint256 _addFee, uint256 _removeFee) external onlyOwner {
        require(_addFee <= 500, "Add fee too high"); // 最大 5%
        require(_removeFee <= 1000, "Remove fee too high"); // 最大 10%
        
        addLiquidityFee = _addFee;
        removeLiquidityFee = _removeFee;
        
        emit FeesUpdated(_addFee, _removeFee);
    }
    
    /**
     * @dev 更新奖励率
     */
    function updateRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate <= 50, "Reward rate too high"); // 最大 50%
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }
    
    /**
     * @dev 紧急提取功能
     */
    function emergencyWithdraw(address tokenAddress, uint256 amount) external onlyOwner {
        if (tokenAddress == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(tokenAddress).transfer(owner(), amount);
        }
    }
    
    // ============ 接收 ETH ============
    
    receive() external payable {}
}