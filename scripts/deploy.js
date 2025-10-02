/**
 * 部署脚本：SHIB 风格 Meme 代币合约部署
 * 
 * 使用方法：
 * npx hardhat run scripts/deploy.js --network [network-name]
 */

const { ethers } = require("hardhat");
const hre = require("hardhat");

// 网络配置
const NETWORK_CONFIG = {
    // 主网配置
    mainnet: {
        uniswapV2Router: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
        weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    },
    // 测试网配置
    goerli: {
        uniswapV2Router: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
        weth: "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6"
    },
    // 本地开发网络
    localhost: {
        uniswapV2Router: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
        weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    }
};

// 代币配置
const TOKEN_CONFIG = {
    name: "ShibaInu Token",
    symbol: "SHIB",
    totalSupply: ethers.utils.parseEther("1000000000000"), // 1万亿代币
    decimals: 18
};

async function main() {
    console.log("🚀 开始部署 SHIB 风格 Meme 代币合约...\n");
    
    // 获取部署者账户
    const [deployer] = await ethers.getSigners();
    console.log("📝 部署账户:", deployer.address);
    console.log("💰 账户余额:", ethers.utils.formatEther(await deployer.getBalance()), "ETH\n");
    
    // 获取网络配置
    const networkName = hre.network.name;
    const config = NETWORK_CONFIG[networkName];
    if (!config) {
        throw new Error(`不支持的网络: ${networkName}`);
    }
    
    console.log("🌐 部署网络:", networkName);
    console.log("🔗 Uniswap Router:", config.uniswapV2Router, "\n");
    
    // 设置钱包地址（在生产环境中应该使用不同的地址）
    const liquidityWallet = deployer.address;
    const marketingWallet = deployer.address;
    
    console.log("💼 流动性钱包:", liquidityWallet);
    console.log("📈 营销钱包:", marketingWallet, "\n");
    
    try {
        // 1. 部署 ShibaInu 代币合约
        console.log("📦 部署 ShibaInu 代币合约...");
        const ShibaInu = await ethers.getContractFactory("ShibaInu");
        const shibToken = await ShibaInu.deploy(
            TOKEN_CONFIG.name,
            TOKEN_CONFIG.symbol,
            TOKEN_CONFIG.totalSupply,
            config.uniswapV2Router,
            liquidityWallet,
            marketingWallet
        );
        
        await shibToken.deployed();
        console.log("✅ ShibaInu 代币合约已部署:", shibToken.address);
        
        // 2. 创建 Uniswap 交易对
        console.log("\n🏪 创建 Uniswap 交易对...");
        const uniswapFactory = await ethers.getContractAt(
            "IUniswapV2Factory",
            "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f" // Uniswap V2 Factory
        );
        
        const createPairTx = await uniswapFactory.createPair(shibToken.address, config.weth);
        await createPairTx.wait();
        
        const pairAddress = await uniswapFactory.getPair(shibToken.address, config.weth);
        console.log("✅ Uniswap 交易对已创建:", pairAddress);
        
        // 3. 设置交易对地址
        console.log("\n⚙️  配置代币合约...");
        const setPairTx = await shibToken.setUniswapV2Pair(pairAddress);
        await setPairTx.wait();
        console.log("✅ 交易对地址已设置");
        
        // 4. 部署流动性池管理合约
        console.log("\n💧 部署流动性池管理合约...");
        const LiquidityPoolManager = await ethers.getContractFactory("LiquidityPoolManager");
        const poolManager = await LiquidityPoolManager.deploy(
            shibToken.address,
            config.uniswapV2Router,
            pairAddress
        );
        
        await poolManager.deployed();
        console.log("✅ 流动性池管理合约已部署:", poolManager.address);
        
        // 5. 验证合约部署
        console.log("\n🔍 验证合约部署...");
        const tokenName = await shibToken.name();
        const tokenSymbol = await shibToken.symbol();
        const tokenSupply = await shibToken.totalSupply();
        const deployerBalance = await shibToken.balanceOf(deployer.address);
        
        console.log("代币名称:", tokenName);
        console.log("代币符号:", tokenSymbol);
        console.log("总供应量:", ethers.utils.formatEther(tokenSupply));
        console.log("部署者余额:", ethers.utils.formatEther(deployerBalance));
        
        // 6. 显示合约地址总结
        console.log("\n" + "=".repeat(60));
        console.log("📋 合约部署总结");
        console.log("=".repeat(60));
        console.log("🪙 ShibaInu Token:       ", shibToken.address);
        console.log("🏪 Uniswap V2 Pair:     ", pairAddress);
        console.log("💧 Pool Manager:        ", poolManager.address);
        console.log("🔗 Uniswap V2 Router:   ", config.uniswapV2Router);
        console.log("💼 Liquidity Wallet:    ", liquidityWallet);
        console.log("📈 Marketing Wallet:     ", marketingWallet);
        console.log("=".repeat(60));
        
        // 7. 保存部署信息到文件
        const deploymentInfo = {
            network: networkName,
            timestamp: new Date().toISOString(),
            contracts: {
                ShibaInu: shibToken.address,
                UniswapV2Pair: pairAddress,
                LiquidityPoolManager: poolManager.address
            },
            config: {
                uniswapV2Router: config.uniswapV2Router,
                liquidityWallet,
                marketingWallet
            },
            tokenConfig: TOKEN_CONFIG
        };
        
        const fs = require('fs');
        const path = require('path');
        
        // 确保 deployments 目录存在
        const deploymentsDir = path.join(__dirname, '..', 'deployments');
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }
        
        const deploymentFile = path.join(deploymentsDir, `${networkName}-deployment.json`);
        fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
        
        console.log(`\n💾 部署信息已保存到: ${deploymentFile}`);
        
        // 8. 如果是测试网络，尝试验证合约
        if (networkName !== 'localhost' && networkName !== 'hardhat') {
            console.log("\n🔐 等待区块确认后验证合约...");
            
            // 等待几个区块确认
            await new Promise(resolve => setTimeout(resolve, 30000));
            
            try {
                await hre.run("verify:verify", {
                    address: shibToken.address,
                    constructorArguments: [
                        TOKEN_CONFIG.name,
                        TOKEN_CONFIG.symbol,
                        TOKEN_CONFIG.totalSupply,
                        config.uniswapV2Router,
                        liquidityWallet,
                        marketingWallet
                    ],
                });
                console.log("✅ ShibaInu 合约验证成功");
            } catch (error) {
                console.log("⚠️  合约验证失败:", error.message);
            }
            
            try {
                await hre.run("verify:verify", {
                    address: poolManager.address,
                    constructorArguments: [
                        shibToken.address,
                        config.uniswapV2Router,
                        pairAddress
                    ],
                });
                console.log("✅ LiquidityPoolManager 合约验证成功");
            } catch (error) {
                console.log("⚠️  流动性池管理合约验证失败:", error.message);
            }
        }
        
        console.log("\n🎉 部署完成！");
        
        // 9. 显示后续操作指南
        console.log("\n" + "=".repeat(60));
        console.log("📚 后续操作指南");
        console.log("=".repeat(60));
        console.log("1. 启用交易:");
        console.log(`   await contract.enableTrading()`);
        console.log("\n2. 添加初始流动性:");
        console.log(`   await contract.approve("${config.uniswapV2Router}", ethers.utils.parseEther("amount"))`);
        console.log(`   在 Uniswap 上添加 ETH/SHIB 流动性`);
        console.log("\n3. 配置税费和限制:");
        console.log(`   await contract.updateTaxes(buyTax, sellTax, liquidityTax, marketingTax, burnTax)`);
        console.log(`   await contract.updateTransactionLimits(maxTx, maxWallet)`);
        console.log("=".repeat(60));
        
    } catch (error) {
        console.error("❌ 部署失败:", error);
        process.exit(1);
    }
}

// 处理错误
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ 部署脚本执行失败:", error);
        process.exit(1);
    });