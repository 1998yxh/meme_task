/**
 * SHIB 风格 Meme 代币合约简化测试套件
 */

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ShibaInuSimple Token 测试", function () {
    let shibToken;
    let poolManager;
    let owner, addr1, addr2, addr3, addr4;
    let liquidityWallet, marketingWallet;
    
    // 测试常量
    const TOTAL_SUPPLY = ethers.parseEther("1000000000"); // 10亿代币
    const TOKEN_NAME = "ShibaInu Token";
    const TOKEN_SYMBOL = "SHIB";
    
    beforeEach(async function () {
        // 获取测试账户
        [owner, addr1, addr2, addr3, addr4] = await ethers.getSigners();
        liquidityWallet = addr1;
        marketingWallet = addr2;
        
        // 模拟 Uniswap 路由器地址
        const routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
        
        // 部署 ShibaInu 代币合约
        const ShibaInu = await ethers.getContractFactory("ShibaInu");
        shibToken = await ShibaInu.deploy(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOTAL_SUPPLY,
            routerAddress,
            liquidityWallet.address,
            marketingWallet.address
        );
        await shibToken.waitForDeployment();
        
        // 设置模拟交易对地址
        const mockPairAddress = addr3.address;
        await shibToken.setUniswapV2Pair(mockPairAddress);
        
        // 部署流动性池管理合约
        const LiquidityPoolManager = await ethers.getContractFactory("LiquidityPoolManager");
        poolManager = await LiquidityPoolManager.deploy(
            await shibToken.getAddress(),
            routerAddress,
            mockPairAddress
        );
        await poolManager.waitForDeployment();
    });
    
    describe("🏗️ 合约部署测试", function () {
        it("应该正确设置代币基本信息", async function () {
            expect(await shibToken.name()).to.equal(TOKEN_NAME);
            expect(await shibToken.symbol()).to.equal(TOKEN_SYMBOL);
            expect(await shibToken.totalSupply()).to.equal(TOTAL_SUPPLY);
            expect(await shibToken.decimals()).to.equal(18);
        });
        
        it("应该将所有代币分配给部署者", async function () {
            const deployerBalance = await shibToken.balanceOf(owner.address);
            expect(deployerBalance).to.equal(TOTAL_SUPPLY);
        });
        
        it("应该正确设置钱包地址", async function () {
            expect(await shibToken.liquidityWallet()).to.equal(liquidityWallet.address);
            expect(await shibToken.marketingWallet()).to.equal(marketingWallet.address);
        });
        
        it("应该正确设置初始税率", async function () {
            const taxInfo = await shibToken.getTaxInfo();
            expect(taxInfo.buyTax_).to.equal(3);
            expect(taxInfo.sellTax_).to.equal(5);
            expect(taxInfo.liquidityTax_).to.equal(2);
            expect(taxInfo.marketingTax_).to.equal(2);
            expect(taxInfo.burnTax_).to.equal(1);
        });
    });
    
    describe("💰 基本 ERC20 功能测试", function () {
        beforeEach(async function () {
            // 启用交易
            await shibToken.enableTrading();
        });
        
        it("应该支持正常转账", async function () {
            const transferAmount = ethers.parseEther("1000");
            
            await shibToken.transfer(addr1.address, transferAmount);
            
            expect(await shibToken.balanceOf(addr1.address)).to.equal(transferAmount);
            expect(await shibToken.balanceOf(owner.address)).to.equal(
                TOTAL_SUPPLY - transferAmount
            );
        });
        
        it("应该支持授权和 transferFrom", async function () {
            const transferAmount = ethers.parseEther("1000");
            
            await shibToken.approve(addr1.address, transferAmount);
            expect(await shibToken.allowance(owner.address, addr1.address)).to.equal(transferAmount);
            
            await shibToken.connect(addr1).transferFrom(owner.address, addr2.address, transferAmount);
            
            expect(await shibToken.balanceOf(addr2.address)).to.equal(transferAmount);
            expect(await shibToken.allowance(owner.address, addr1.address)).to.equal(0);
        });
    });
    
    describe("📊 代币税机制测试", function () {
        beforeEach(async function () {
            await shibToken.enableTrading();
            await shibToken.setUniswapV2Pair(addr3.address);
        });
        
        it("普通转账不应收取税费", async function () {
            const transferAmount = ethers.parseEther("1000");
            
            await shibToken.transfer(addr1.address, transferAmount);
            
            expect(await shibToken.balanceOf(addr1.address)).to.equal(transferAmount);
        });
        
        it("从交易对购买应收取买入税", async function () {
            const buyAmount = ethers.parseEther("1000");
            
            // 首先给交易对地址一些代币（所有者转账不收税）
            await shibToken.transfer(addr3.address, buyAmount);
            
            // 确保参与转账的地址都不被排除在税费之外
            await shibToken.excludeFromFees(addr3.address, false);
            await shibToken.excludeFromFees(addr1.address, false);
            
            // 记录转账前的余额
            const addr1BalanceBefore = await shibToken.balanceOf(addr1.address);
            const contractBalanceBefore = await shibToken.balanceOf(await shibToken.getAddress());
            
            // 从交易对转账给 addr1（模拟买入）
            await shibToken.connect(addr3).transfer(addr1.address, buyAmount);
            
            // 由于买入税为3%，用户应该收到97%的代币
            const expectedAmount = buyAmount * 97n / 100n;
            const addr1BalanceAfter = await shibToken.balanceOf(addr1.address);
            expect(addr1BalanceAfter - addr1BalanceBefore).to.equal(expectedAmount);
            
            // 合约应该收到3%的税费
            const expectedTax = buyAmount * 3n / 100n;
            const contractBalanceAfter = await shibToken.balanceOf(await shibToken.getAddress());
            expect(contractBalanceAfter - contractBalanceBefore).to.equal(expectedTax);
        });
        
        it("卖给交易对应收取卖出税", async function () {
            const sellAmount = ethers.parseEther("1000");
            
            // 首先给 addr1 一些代币（绕过税费）
            await shibToken.excludeFromFees(addr1.address, true);
            await shibToken.transfer(addr1.address, sellAmount);
            await shibToken.excludeFromFees(addr1.address, false);
            
            // addr1 卖给交易对（模拟卖出）
            await shibToken.connect(addr1).transfer(addr3.address, sellAmount);
            
            // 由于卖出税为5%，交易对应该收到95%的代币
            const expectedAmount = sellAmount * 95n / 100n;
            expect(await shibToken.balanceOf(addr3.address)).to.equal(expectedAmount);
        });
    });
    
    describe("🚫 交易限制功能测试", function () {
        beforeEach(async function () {
            await shibToken.enableTrading();
            await shibToken.setUniswapV2Pair(addr3.address);
        });
        
        it("应该阻止黑名单地址交易", async function () {
            const transferAmount = ethers.parseEther("1000");
            
            // 将 addr1 加入黑名单
            await shibToken.updateBlacklist(addr1.address, true);
            
            // 尝试转账给黑名单地址应该失败
            await expect(
                shibToken.transfer(addr1.address, transferAmount)
            ).to.be.revertedWith("Blacklisted address");
        });
        
        it("应该限制单笔交易金额", async function () {
            // 如果交易还没启用，先启用
            const limitsInfo = await shibToken.getLimitsInfo();
            if (!limitsInfo.tradingEnabled_) {
                await shibToken.enableTrading();
            }
            
            // 设置最小允许的限制（总供应量的0.1% = 1000000代币）
            const newMaxTx = ethers.parseEther("1000000"); // 100万代币
            await shibToken.updateTransactionLimits(newMaxTx, ethers.parseEther("5000000")); // 500万代币
            
            const exceedAmount = newMaxTx + ethers.parseEther("1");
            
            // 给 addr4 足够的代币（addr4不是免限制用户）
            await shibToken.transfer(addr4.address, exceedAmount + ethers.parseEther("1000"));
            
            // 从 addr4 转账给另一个非免限制用户，应该失败
            const addr5 = (await ethers.getSigners())[5];
            await expect(
                shibToken.connect(addr4).transfer(addr5.address, exceedAmount)
            ).to.be.revertedWith("Transfer amount exceeds the maxTransactionAmount");
        });
        
        it("应该限制钱包最大持有量", async function () {
            // 如果交易还没启用，先启用
            const limitsInfo = await shibToken.getLimitsInfo();
            if (!limitsInfo.tradingEnabled_) {
                await shibToken.enableTrading();
            }
            
            // 设置最小允许的限制（总供应量的0.5% = 5000000代币）
            const newMaxWallet = ethers.parseEther("5000000"); // 500万代币
            await shibToken.updateTransactionLimits(ethers.parseEther("1000000"), newMaxWallet);
            
            // 给 addr4 最大限制的代币
            await shibToken.transfer(addr4.address, newMaxWallet);
            
            // 从其他非免限制地址尝试再转给 addr4 超过限制
            const addr5 = (await ethers.getSigners())[5];
            await shibToken.transfer(addr5.address, ethers.parseEther("100"));
            
            await expect(
                shibToken.connect(addr5).transfer(addr4.address, ethers.parseEther("1"))
            ).to.be.revertedWith("Exceeds maximum wallet token amount");
        });
    });
    
    describe("⚙️ 管理员功能测试", function () {
        it("只有所有者能够启用交易", async function () {
            await expect(
                shibToken.connect(addr1).enableTrading()
            ).to.be.revertedWithCustomError(shibToken, "OwnableUnauthorizedAccount");
            
            await shibToken.enableTrading();
            expect(await shibToken.tradingEnabled()).to.be.true;
        });
        
        it("只有所有者能够更新税率", async function () {
            await expect(
                shibToken.connect(addr1).updateTaxes(2, 4, 1, 1, 1)
            ).to.be.revertedWithCustomError(shibToken, "OwnableUnauthorizedAccount");
            
            await shibToken.updateTaxes(2, 4, 1, 1, 1);
            
            const taxInfo = await shibToken.getTaxInfo();
            expect(taxInfo.buyTax_).to.equal(2);
            expect(taxInfo.sellTax_).to.equal(4);
        });
        
        it("应该阻止设置过高的税率", async function () {
            await expect(
                shibToken.updateTaxes(15, 20, 5, 5, 5)
            ).to.be.revertedWith("Buy tax too high");
        });
        
        it("只有所有者能够更新交易限制", async function () {
            const newMaxTx = ethers.parseEther("5000000"); // 500万代币
            const newMaxWallet = ethers.parseEther("10000000"); // 1000万代币
            
            await expect(
                shibToken.connect(addr1).updateTransactionLimits(newMaxTx, newMaxWallet)
            ).to.be.revertedWithCustomError(shibToken, "OwnableUnauthorizedAccount");
            
            await shibToken.updateTransactionLimits(newMaxTx, newMaxWallet);
            
            expect(await shibToken.maxTransactionAmount()).to.equal(newMaxTx);
            expect(await shibToken.maxWalletAmount()).to.equal(newMaxWallet);
        });
    });
    
    describe("💧 流动性池管理测试", function () {
        beforeEach(async function () {
            // 给流动性池管理合约一些代币用于奖励
            await shibToken.transfer(await poolManager.getAddress(), ethers.parseEther("1000000"));
        });
        
        it("应该正确初始化池管理合约", async function () {
            expect(await poolManager.token()).to.equal(await shibToken.getAddress());
            expect(await poolManager.totalProviders()).to.equal(0);
            expect(await poolManager.rewardRate()).to.equal(12);
        });
        
        it("只有所有者能够更新费用设置", async function () {
            await expect(
                poolManager.connect(addr1).updateFees(100, 200)
            ).to.be.revertedWithCustomError(poolManager, "OwnableUnauthorizedAccount");
            
            await poolManager.updateFees(100, 200);
            expect(await poolManager.addLiquidityFee()).to.equal(100);
            expect(await poolManager.removeLiquidityFee()).to.equal(200);
        });
        
        it("应该阻止设置过高的费用", async function () {
            await expect(
                poolManager.updateFees(600, 2000) // 6%, 20%
            ).to.be.revertedWith("Add fee too high");
        });
    });
    
    describe("🔍 查询功能测试", function () {
        it("应该正确返回账户统计信息", async function () {
            await shibToken.enableTrading();
            const transferAmount = ethers.parseEther("1000");
            
            // 使用 addr4，它不是免费用户也不是特殊地址
            await shibToken.transfer(addr4.address, transferAmount);
            
            const stats = await shibToken.getAccountStats(addr4.address);
            expect(stats.balance).to.equal(transferAmount);
            expect(stats.isExcludedFromFees_).to.be.false;
            expect(stats.isExcludedFromLimits_).to.be.false;
            expect(stats.isBlacklisted).to.be.false;
        });
        
        it("应该正确返回限制信息", async function () {
            const limitsInfo = await shibToken.getLimitsInfo();
            expect(limitsInfo.tradingEnabled_).to.be.false; // 默认未启用
            expect(limitsInfo.transactionCooldown_).to.equal(30);
            expect(limitsInfo.maxDailyTransactions_).to.equal(10);
        });
        
        it("应该正确返回池统计信息", async function () {
            const poolStats = await poolManager.getPoolStats();
            expect(poolStats.totalProviders_).to.equal(0);
            expect(poolStats.currentRewardRate).to.equal(12);
        });
    });
    
    describe("🚨 边界条件测试", function () {
        it("应该处理零金额转账", async function () {
            await shibToken.enableTrading();
            
            await expect(
                shibToken.transfer(addr1.address, 0)
            ).to.be.revertedWith("Transfer amount must be greater than zero");
        });
        
        it("应该处理到零地址的转账", async function () {
            await shibToken.enableTrading();
            const transferAmount = ethers.parseEther("1000");
            
            await expect(
                shibToken.transfer(ethers.ZeroAddress, transferAmount)
            ).to.be.revertedWithCustomError(shibToken, "ERC20InvalidReceiver");
        });
        
        it("应该处理余额不足的转账", async function () {
            await shibToken.enableTrading();
            const excessiveAmount = TOTAL_SUPPLY + ethers.parseEther("1");
            
            await expect(
                shibToken.transfer(addr1.address, excessiveAmount)
            ).to.be.revertedWithCustomError(shibToken, "ERC20InsufficientBalance");
        });
    });
});