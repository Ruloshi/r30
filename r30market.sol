// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * R30 Market — simple peer-to-peer swap of $R30 for ETH.
 *
 *  - A seller lists an amount of $R30 for a total price in ETH. The tokens are
 *    held in escrow by this contract until the listing is bought or cancelled.
 *  - A buyer pays the exact price in ETH; in the same transaction the buyer
 *    receives the tokens and the seller receives the ETH minus a 3% fee.
 *  - A listing cannot be edited: to change the price, cancel and list again.
 *    (This also protects buyers from a price change just before they buy.)
 *  - The market opens only once the Rule 30 Pyramid mint is closed
 *    (token.mintClosed() == true).
 *  - The fee is fixed in the code (3%) and cannot be changed.
 *
 * Needs the R30 token address at deployment (the R30 contract, not the Market).
 */

interface IR30 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function mintClosed() external view returns (bool);
}

contract R30Market {
    // ─────────────── Constants ───────────────
    uint256 public constant FEE_BPS    = 300;      // 3% (basis points)
    uint256 private constant BPS       = 10_000;
    uint256 public constant MIN_AMOUNT = 1e18;     // minimum 1 R30 per listing (R30 has 18 decimals)

    // ─────────────── Types ───────────────
    enum Status { Active, Sold, Cancelled }

    struct Listing {
        address seller;
        uint256 amount;   // R30 in escrow (18 decimals)
        uint256 price;    // total price in wei
        Status  status;
    }

    // ─────────────── State ───────────────
    IR30    public immutable token;
    address public owner;
    address public feeWallet;

    Listing[] private _listings;

    uint256 public accruedFees;   // ETH fees waiting to be sent to feeWallet
    uint256 public totalVolume;   // total ETH traded (wei)
    uint256 public totalSales;    // number of completed sales

    uint256 private _lock = 1;

    // ─────────────── Events ───────────────
    event Listed(uint256 indexed id, address indexed seller, uint256 amount, uint256 price);
    event Sold(uint256 indexed id, address indexed buyer, address indexed seller, uint256 amount, uint256 price, uint256 fee);
    event Cancelled(uint256 indexed id, address indexed seller);
    event FeesWithdrawn(address indexed to, uint256 amount);
    event FeeWalletUpdated(address indexed newWallet);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─────────────── Modifiers ───────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(_lock == 1, "Reentrant call");
        _lock = 2;
        _;
        _lock = 1;
    }

    modifier whenOpen() {
        require(token.mintClosed(), "Market opens when the mint is complete");
        _;
    }

    // ─────────────── Constructor ───────────────
    constructor(address r30Token, address feeWallet_) {
        require(r30Token != address(0), "Invalid token");
        require(feeWallet_ != address(0), "Invalid fee wallet");
        token = IR30(r30Token);
        feeWallet = feeWallet_;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─────────────── Seller: list ───────────────
    /// Put `amount` R30 on sale for `price` wei in total.
    /// The seller must first call approve(market, amount) on the R30 token.
    function list(uint256 amount, uint256 price) external whenOpen nonReentrant returns (uint256 id) {
        require(amount >= MIN_AMOUNT, "Amount too small");
        require(price > 0, "Price must be > 0");

        id = _listings.length;
        _listings.push(Listing({
            seller: msg.sender,
            amount: amount,
            price:  price,
            status: Status.Active
        }));

        require(token.transferFrom(msg.sender, address(this), amount), "Token transfer failed");
        emit Listed(id, msg.sender, amount, price);
    }

    // ─────────────── Buyer: buy ───────────────
    /// Buy a whole listing by sending exactly its price in ETH.
    function buy(uint256 id) external payable whenOpen nonReentrant {
        require(id < _listings.length, "No such listing");
        Listing storage l = _listings[id];
        require(l.status == Status.Active, "Listing not active");
        require(msg.value == l.price, "Wrong ETH amount");
        require(l.seller != msg.sender, "Cannot buy your own listing");

        // effects
        l.status = Status.Sold;
        uint256 fee      = (l.price * FEE_BPS) / BPS;
        uint256 proceeds = l.price - fee;
        accruedFees += fee;
        totalVolume += l.price;
        totalSales  += 1;

        // interactions
        require(token.transfer(msg.sender, l.amount), "Token transfer failed");
        (bool ok, ) = payable(l.seller).call{value: proceeds}("");
        require(ok, "Payment to seller failed");

        emit Sold(id, msg.sender, l.seller, l.amount, l.price, fee);
    }

    // ─────────────── Seller: cancel ───────────────
    /// Cancel your active listing and get your tokens back.
    function cancel(uint256 id) external nonReentrant {
        require(id < _listings.length, "No such listing");
        Listing storage l = _listings[id];
        require(l.seller == msg.sender, "Not your listing");
        require(l.status == Status.Active, "Listing not active");

        l.status = Status.Cancelled;
        require(token.transfer(msg.sender, l.amount), "Token transfer failed");
        emit Cancelled(id, msg.sender);
    }

    // ─────────────── Fees ───────────────
    /// Send the accumulated fees to the fee wallet. Anyone can call it;
    /// the ETH always goes to feeWallet.
    function withdrawFees() external nonReentrant {
        uint256 amount = accruedFees;
        require(amount > 0, "No fees");
        accruedFees = 0;
        (bool ok, ) = payable(feeWallet).call{value: amount}("");
        require(ok, "Fee transfer failed");
        emit FeesWithdrawn(feeWallet, amount);
    }

    // ─────────────── Views ───────────────
    function isOpen() external view returns (bool) {
        return token.mintClosed();
    }

    function listingCount() external view returns (uint256) {
        return _listings.length;
    }

    function getListing(uint256 id) external view returns (Listing memory) {
        require(id < _listings.length, "No such listing");
        return _listings[id];
    }

    /// Returns up to `count` listings starting at index `from` (active, sold and cancelled).
    function getListings(uint256 from, uint256 count) external view returns (Listing[] memory out) {
        uint256 n = _listings.length;
        if (from >= n) {
            return new Listing[](0);
        }
        uint256 end = from + count;
        if (end > n) end = n;
        out = new Listing[](end - from);
        for (uint256 i = from; i < end; i++) {
            out[i - from] = _listings[i];
        }
    }

    // ─────────────── Admin ───────────────
    function setFeeWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Invalid address");
        feeWallet = newWallet;
        emit FeeWalletUpdated(newWallet);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// Give up ownership: the fee wallet can no longer be changed.
    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }
}
