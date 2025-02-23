// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/// @title IkigaiToken - Advanced ERC20 with marketplace and deflationary features
contract IkigaiToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuard, Pausable {
    // --- Marketplace Structures ---
    struct ArtListing {
        address seller;
        uint256 price;
        bool active;
        uint256 royaltyPercentage;
        uint256 creatorFee;      // Additional creator fee
        address creator;         // Original creator address
    }

    struct MarketplaceConfig {
        uint256 baseFee;        // Base marketplace fee (basis points)
        uint256 burnRate;       // Token burn rate (basis points)
        uint256 maxRoyalty;     // Maximum royalty percentage
        uint256 minPrice;       // Minimum listing price
    }

    // --- State Variables ---
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;
    uint256 public totalMinted;
    uint256 public totalBurned;

    // Marketplace state
    mapping(uint256 => ArtListing) public artListings;
    MarketplaceConfig public marketConfig;
    address public marketplace;
    mapping(address => bool) public isExemptFromFees;
    
    // Minting permissions
    mapping(address => bool) public authorizedMinters;
    
    // Transfer limits
    uint256 public maxTransferAmount;
    mapping(address => bool) public isExemptFromLimit;
    
    // Anti-bot protection
    mapping(address => uint256) public lastTransferTimestamp;
    uint256 public transferCooldown;
    
    // Trading control
    bool public tradingEnabled;
    mapping(address => bool) public isExemptFromTradingRestriction;

    // Staking state
    mapping(address => uint256) public stakingInfo;
    uint256 public totalStaked;

    // Emission control variables
    struct EmissionControl {
        uint256 dailyLimit;
        uint256 weeklyLimit;
        uint256 monthlyLimit;
        uint256 lastUpdateTime;
        uint256 dailyMinted;
        uint256 weeklyMinted;
        uint256 monthlyMinted;
    }

    EmissionControl public emissionControl;

    // Add security-focused modifiers and constants
    modifier validAmount(uint256 amount) {
        require(amount > 0 && amount <= maxTransferAmount, "Invalid amount");
        _;
    }

    modifier validRecipient(address to) {
        require(
            to != address(0) && 
            to != address(this) &&
            !blacklisted[to],
            "Invalid recipient"
        );
        _;
    }

    modifier whenTradingEnabled() {
        require(
            tradingEnabled || 
            isExemptFromTradingRestriction[msg.sender],
            "Trading not enabled"
        );
        _;
    }

    // Add security constants
    uint256 private constant MAX_FEE = 2000;         // 20% max fee
    uint256 private constant MIN_LIQUIDITY = 1000;   // Minimum liquidity check
    uint256 private constant RATE_LIMIT_PERIOD = 1 hours;
    uint256 private constant MAX_ACTIONS_PER_PERIOD = 100;

    // Add rate limiting
    struct RateLimit {
        uint256 lastReset;
        uint256 count;
    }
    mapping(address => RateLimit) public rateLimits;

    // Add to state variables
    bool public transfersPaused;
    mapping(address => bool) public isContract;
    uint256 public liquidityThreshold;

    // Add security events
    event SecurityLimitExceeded(address indexed account, string limitType);
    event ContractBlacklisted(address indexed account);
    event EmergencyTransfersPaused(bool paused);
    event RateLimitExceeded(address indexed account);

    // --- Events ---
    event ArtListed(
        uint256 indexed tokenId, 
        address indexed seller,
        uint256 price, 
        uint256 royaltyPercentage
    );
    event ArtSold(
        uint256 indexed tokenId, 
        address indexed seller, 
        address indexed buyer, 
        uint256 price
    );
    event TokensBurned(address indexed from, uint256 amount);
    event MarketplaceConfigUpdated(string param, uint256 value);
    event RoyaltyPaid(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 amount
    );
    event MinterStatusUpdated(address indexed minter, bool status);
    event TransferLimitUpdated(uint256 newLimit);
    event TransferCooldownUpdated(uint256 newCooldown);
    event TradingStatusUpdated(bool enabled);
    event ExemptionStatusUpdated(address indexed account, string exemptionType, bool status);

    /// @notice Initialize the token with marketplace features
    function initialize() public initializer {
        __ERC20_init("Ikigai", "IKIGAI");
        __Ownable_init();
        
        maxTransferAmount = 1_000_000 * 1e18; // 1M tokens
        transferCooldown = 1 minutes;
        tradingEnabled = false;
        
        // Exempt owner from restrictions
        isExemptFromLimit[owner()] = true;
        isExemptFromTradingRestriction[owner()] = true;

        marketConfig = MarketplaceConfig({
            baseFee: 250,      // 2.5% base fee
            burnRate: 100,     // 1% burn rate
            maxRoyalty: 1000,  // 10% max royalty
            minPrice: 100 * 1e18 // 100 IKIGAI minimum
        });

        marketplace = msg.sender;
        isExemptFromFees[marketplace] = true;

        emissionControl = EmissionControl({
            dailyLimit: totalSupply() * 1 / 1000,    // 0.1% daily
            weeklyLimit: totalSupply() * 5 / 1000,   // 0.5% weekly
            monthlyLimit: totalSupply() * 20 / 1000, // 2% monthly
            lastUpdateTime: block.timestamp,
            dailyMinted: 0,
            weeklyMinted: 0,
            monthlyMinted: 0
        });
    }

    // --- Security Modifiers ---
    modifier whenTradingEnabled() {
        require(
            tradingEnabled || isExemptFromTradingRestriction[msg.sender],
            "Trading not enabled"
        );
        _;
    }

    modifier checkTransferLimit(uint256 amount) {
        require(
            amount <= maxTransferAmount || isExemptFromLimit[msg.sender],
            "Transfer exceeds limit"
        );
        _;
    }

    modifier checkTransferCooldown() {
        require(
            block.timestamp >= lastTransferTimestamp[msg.sender] + transferCooldown ||
            isExemptFromLimit[msg.sender],
            "Transfer cooldown active"
        );
        _;
    }

    // --- Marketplace Functions ---

    /// @notice List art for sale
    function listArt(
        uint256 tokenId, 
        uint256 price,
        uint256 royaltyPercentage,
        address creator
    ) external nonReentrant {
        require(price >= marketConfig.minPrice, "Price too low");
        require(royaltyPercentage <= marketConfig.maxRoyalty, "Royalty too high");
        
        artListings[tokenId] = ArtListing({
            seller: msg.sender,
            price: price,
            active: true,
            royaltyPercentage: royaltyPercentage,
            creatorFee: 0,
            creator: creator
        });
        
        emit ArtListed(tokenId, msg.sender, price, royaltyPercentage);
    }

    /// @notice Buy listed art
    function buyArt(uint256 tokenId) external nonReentrant {
        ArtListing storage listing = artListings[tokenId];
        require(listing.active, "Not for sale");
        
        uint256 price = listing.price;
        address seller = listing.seller;
        
        // Calculate fees
        uint256 marketplaceFee = (price * marketConfig.baseFee) / 10000;
        uint256 burnAmount = (price * marketConfig.burnRate) / 10000;
        uint256 royalty = (price * listing.royaltyPercentage) / 10000;
        uint256 sellerAmount = price - marketplaceFee - burnAmount - royalty;
        
        // Execute transfers
        require(transfer(marketplace, marketplaceFee), "Marketplace fee failed");
        _burn(msg.sender, burnAmount);
        require(transfer(seller, sellerAmount), "Seller transfer failed");
        
        if (royalty > 0 && listing.creator != address(0)) {
            require(transfer(listing.creator, royalty), "Royalty transfer failed");
            emit RoyaltyPaid(tokenId, listing.creator, royalty);
        }
        
        totalBurned += burnAmount;
        listing.active = false;
        
        emit ArtSold(tokenId, seller, msg.sender, price);
        emit TokensBurned(msg.sender, burnAmount);
    }

    // --- Enhanced Token Functions ---

    /// @notice Override transfer with burn mechanism
    function transfer(
        address to, 
        uint256 amount
    ) public virtual override whenNotPaused whenTradingEnabled returns (bool) {
        require(!transfersPaused, "Transfers paused");
        require(_checkRateLimit(msg.sender), "Rate limit exceeded");
        
        // Validate transfer
        require(amount <= maxTransferAmount || isExemptFromLimit[msg.sender], "Exceeds limit");
        require(
            block.timestamp >= lastTransferTimestamp[msg.sender] + transferCooldown || 
            isExemptFromLimit[msg.sender],
            "Cooldown active"
        );

        // Check recipient
        if (!isExemptFromTradingRestriction[to]) {
            require(!_isContract(to), "Cannot transfer to contract");
            require(balanceOf(to) + amount <= maxWalletSize, "Exceeds wallet size");
        }

        // Process fees if applicable
        uint256 finalAmount = amount;
        if (!isExemptFromFees[msg.sender] && !isExemptFromFees[to]) {
            uint256 burnAmount = _calculateBurnAmount(amount);
            finalAmount = amount - burnAmount;
            _burn(msg.sender, burnAmount);
            totalBurned += burnAmount;
            emit TokensBurned(msg.sender, burnAmount);
        }

        // Update rate limit and timestamp
        _updateRateLimit(msg.sender);
        lastTransferTimestamp[msg.sender] = block.timestamp;

        return super.transfer(to, finalAmount);
    }

    // --- Admin Functions ---

    /// @notice Update marketplace configuration
    function updateMarketConfig(
        uint256 _baseFee,
        uint256 _burnRate,
        uint256 _maxRoyalty,
        uint256 _minPrice
    ) external onlyOwner {
        require(_baseFee <= 1000, "Base fee too high"); // Max 10%
        require(_burnRate <= 500, "Burn rate too high"); // Max 5%
        require(_maxRoyalty <= 2000, "Max royalty too high"); // Max 20%

        marketConfig.baseFee = _baseFee;
        marketConfig.burnRate = _burnRate;
        marketConfig.maxRoyalty = _maxRoyalty;
        marketConfig.minPrice = _minPrice;

        emit MarketplaceConfigUpdated("baseFee", _baseFee);
        emit MarketplaceConfigUpdated("burnRate", _burnRate);
        emit MarketplaceConfigUpdated("maxRoyalty", _maxRoyalty);
        emit MarketplaceConfigUpdated("minPrice", _minPrice);
    }

    /// @notice Set fee exemption status
    function setFeeExempt(address account, bool exempt) external onlyOwner {
        isExemptFromFees[account] = exempt;
    }

    /// @notice Update minter authorization
    function setMinterStatus(address minter, bool status) external onlyOwner {
        authorizedMinters[minter] = status;
        emit MinterStatusUpdated(minter, status);
    }

    /// @notice Update transfer limit
    function setTransferLimit(uint256 newLimit) external onlyOwner {
        require(newLimit > 0, "Invalid limit");
        maxTransferAmount = newLimit;
        emit TransferLimitUpdated(newLimit);
    }

    /// @notice Update transfer cooldown
    function setTransferCooldown(uint256 newCooldown) external onlyOwner {
        transferCooldown = newCooldown;
        emit TransferCooldownUpdated(newCooldown);
    }

    /// @notice Enable/disable trading
    function setTradingEnabled(bool enabled) external onlyOwner {
        tradingEnabled = enabled;
        emit TradingStatusUpdated(enabled);
    }

    /// @notice Update transfer limit exemption status
    function setTransferLimitExempt(address account, bool exempt) external onlyOwner {
        isExemptFromLimit[account] = exempt;
        emit ExemptionStatusUpdated(account, "transferLimit", exempt);
    }

    /// @notice Update trading restriction exemption status
    function setTradingRestrictionExempt(address account, bool exempt) external onlyOwner {
        isExemptFromTradingRestriction[account] = exempt;
        emit ExemptionStatusUpdated(account, "tradingRestriction", exempt);
    }

    /// @notice Pause all token transfers
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause token transfers
    function unpause() external onlyOwner {
        _unpause();
    }

    // --- View Functions ---

    /// @notice Get account details
    function getAccountDetails(address account) external view returns (
        uint256 balance,
        uint256 timeUntilNextTransfer,
        bool isLimitExempt,
        bool isTradingExempt
    ) {
        balance = balanceOf(account);
        
        uint256 nextTransfer = lastTransferTimestamp[account] + transferCooldown;
        timeUntilNextTransfer = block.timestamp >= nextTransfer ? 0 : nextTransfer - block.timestamp;
        
        isLimitExempt = isExemptFromLimit[account];
        isTradingExempt = isExemptFromTradingRestriction[account];
    }

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        require(transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        stakingInfo[msg.sender].balance += amount;
        totalStaked += amount;
        
        rewards.handleStakeReward(msg.sender, amount);
    }

    // Add burn function
    function burn(uint256 amount) external {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        totalBurned += amount;
        emit TokensBurned(msg.sender, amount);
    }

    // Modify mint function to include emission controls
    function mint(
        address to, 
        uint256 amount
    ) external validRecipient(to) {
        require(authorizedMinters[msg.sender], "Not authorized");
        require(_checkEmissionLimits(amount), "Exceeds emission limits");
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        
        // Check recipient limits
        if (!isExemptFromLimit[to]) {
            require(balanceOf(to) + amount <= maxWalletSize, "Exceeds wallet size");
        }
        
        _updateEmissionTracking(amount);
        _mint(to, amount);
        totalMinted += amount;
    }

    function _checkEmissionLimits(uint256 amount) internal view returns (bool) {
        return emissionControl.dailyMinted + amount <= emissionControl.dailyLimit &&
               emissionControl.weeklyMinted + amount <= emissionControl.weeklyLimit &&
               emissionControl.monthlyMinted + amount <= emissionControl.monthlyLimit;
    }

    function _updateEmissionTracking(uint256 amount) internal {
        uint256 timeElapsed = block.timestamp - emissionControl.lastUpdateTime;
        
        // Reset daily
        if (timeElapsed >= 1 days) {
            emissionControl.dailyMinted = 0;
        }
        
        // Reset weekly
        if (timeElapsed >= 7 days) {
            emissionControl.weeklyMinted = 0;
        }
        
        // Reset monthly
        if (timeElapsed >= 30 days) {
            emissionControl.monthlyMinted = 0;
        }
        
        emissionControl.dailyMinted += amount;
        emissionControl.weeklyMinted += amount;
        emissionControl.monthlyMinted += amount;
        emissionControl.lastUpdateTime = block.timestamp;
    }

    // Add contract detection
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0 || isContract[account];
    }

    // Add rate limiting
    function _checkRateLimit(address account) internal view returns (bool) {
        if (isExemptFromLimit[account]) return true;
        
        RateLimit storage limit = rateLimits[account];
        if (block.timestamp >= limit.lastReset + RATE_LIMIT_PERIOD) {
            return true;
        }
        return limit.count < MAX_ACTIONS_PER_PERIOD;
    }

    function _updateRateLimit(address account) internal {
        if (isExemptFromLimit[account]) return;
        
        RateLimit storage limit = rateLimits[account];
        if (block.timestamp >= limit.lastReset + RATE_LIMIT_PERIOD) {
            limit.count = 1;
            limit.lastReset = block.timestamp;
        } else {
            limit.count++;
        }
    }

    // Add emergency functions
    function pauseTransfers() external onlyOwner {
        transfersPaused = true;
        emit EmergencyTransfersPaused(true);
    }

    function unpauseTransfers() external onlyOwner {
        transfersPaused = false;
        emit EmergencyTransfersPaused(false);
    }

    function setContractStatus(address account, bool isContractAddress) external onlyOwner {
        isContract[account] = isContractAddress;
    }

    // Add liquidity protection
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        
        // Check liquidity on sells
        if (
            !isExemptFromLimit[from] && 
            to == uniswapV2Pair &&
            balanceOf(uniswapV2Pair) - amount < liquidityThreshold
        ) {
            revert("Insufficient liquidity");
        }
    }

    // Add adaptive burn rate calculation
    function _calculateBurnAmount(uint256 amount) internal view returns (uint256) {
        uint256 burnRate = _getAdaptiveBurnRate();
        return (amount * burnRate) / BASIS_POINTS;
    }

    function _getAdaptiveBurnRate() internal view returns (uint256) {
        uint256 marketCap = totalSupply() * getCurrentPrice(); // Implement price oracle
        
        if (marketCap >= 100_000_000 ether) return 400;      // 4%
        if (marketCap >= 50_000_000 ether) return 300;       // 3%
        if (marketCap >= 10_000_000 ether) return 200;       // 2%
        return 100;                                          // 1%
    }
}