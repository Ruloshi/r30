// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * ============================================================
 *  $R30 — Rule 30 Pyramid Mint Contract
 *  Deployed on Ethereum Mainnet
 * ============================================================
 *  - Max supply       : 30,000,000 R30
 *  - Tokens per agent  : 3,000 R30
 *  - Total cells      : 10,000 (100 rows, triangular pyramid)
 *  - Price per mint   : 0.01 ETH (adjustable only BEFORE startMint(),
 *                       capped at MAX_MINT_PRICE = 0.015 ETH)
 *  - Once startMint() is called, mintPrice and liquidityWallet are
 *    permanently locked
 *  - Rule 30 can be computed on-chain on demand (getCellState / getRowBits,
 *    free reads) so anyone can verify a cell's state. Minting does not use it:
 *    the Alive/Dead state does not affect price or tokens received.
 *  - Owner gets 3,000 free agents (30%, top of pyramid) via ownerMintAll()
 *  - Public mints remaining 7,000 agents individually at mintPrice
 *  - Protected against reentrancy attacks
 *  - Owner can emergency-close the mint (closeMint), even before all
 *    agents are sold: the market then opens with the agents minted so far
 *  - Owner can renounce ownership only AFTER the mint is closed, so the
 *    launch can never be left unfinished
 * ============================================================
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Rule30 is IERC20 {

    // ─── ERC20 ──────────────────────────────────────────────────
    string public constant name     = "Rule 30";
    string public constant symbol   = "R30";
    uint8  public constant decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // ─── OWNERSHIP ──────────────────────────────────────────────
    address public owner;
    address public liquidityWallet;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipRenounced(address indexed previousOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    // ─── REENTRANCY GUARD ───────────────────────────────────────
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED     = 2;

    modifier nonReentrant() {
        require(_status != _ENTERED, "Reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // ─── CONFIG ─────────────────────────────────────────────────
    uint256 public constant MAX_SUPPLY       = 30_000_000 * 10**18;
    uint256 public constant TOKENS_PER_AGENT = 3_000 * 10**18;
    uint256 public constant MAX_AGENTS       = 10_000;
    uint256 public constant OWNER_AGENTS     = 3_000; // 30% free for owner

    uint8  public constant ROWS   = 100;
    uint16 public constant COLS   = 201;
    uint16 public constant CENTER = 100;

    uint256 public constant MAX_MINT_PRICE = 0.015 ether; // hard cap on mint price
    uint256 public mintPrice = 0.01 ether; // adjustable via setMintPrice() before startMint()

    mapping(uint8 => mapping(uint16 => address)) public agentOwner;
    uint256 public totalAgentsMinted;
    uint256 public ownerAgentsMinted;
    address public allocationHolder; // address that received the owner allocation (fixed at ownerMintAll)
    bool    public mintStarted; // once true, price and liquidity wallet are locked forever
    bool    public mintClosed;

    // ─── EVENTS ─────────────────────────────────────────────────
    event AgentMinted(address indexed minter, uint8 row, uint16 col, uint256 total);
    event MintStarted(uint256 price, address liquidityWallet);
    event MintClosed(uint256 finalSupply);
    event PriceUpdated(uint256 newPrice);
    event Withdrawn(address indexed to, uint256 amount);
    event LiquidityWalletUpdated(address indexed newWallet);

    // ─── CONSTRUCTOR ────────────────────────────────────────────
    constructor(address _liquidityWallet) {
        require(_liquidityWallet != address(0), "Invalid liquidity wallet");
        owner           = msg.sender;
        liquidityWallet = _liquidityWallet;
        _status         = _NOT_ENTERED;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── RULE 30 — computed on-the-fly ──────────────────────────
    function _nextRow(uint256 prev) internal pure returns (uint256) {
        uint256 next = 0;
        for (uint16 c = 0; c < COLS; c++) {
            uint8 l = (c > 0)        ? uint8((prev >> (c - 1)) & 1) : 0;
            uint8 m =                  uint8((prev >> c)        & 1);
            uint8 r = (c < COLS - 1) ? uint8((prev >> (c + 1)) & 1) : 0;
            uint8 idx = (l << 2) | (m << 1) | r;
            if ((30 >> idx) & 1 == 1) next |= (uint256(1) << c);
        }
        return next;
    }

    function getRowBits(uint8 targetRow) public pure returns (uint256) {
        uint256 bits = uint256(1) << CENTER;
        for (uint8 r = 0; r < targetRow; r++) {
            bits = _nextRow(bits);
        }
        return bits;
    }

    function getCellState(uint8 row, uint16 col) public pure returns (uint8) {
        require(row < ROWS, "Row out of bounds");
        require(col < COLS, "Col out of bounds");
        return uint8((getRowBits(row) >> col) & 1);
    }

    function isAgentMinted(uint8 row, uint16 col) public view returns (bool) {
        uint256 idx = _coordsToIndex(row, col);
        if (idx < OWNER_AGENTS) {
            // The first OWNER_AGENTS cells (top of the pyramid) belong to
            // the owner's 30% allocation. They are considered minted as
            // soon as ownerMintAll() has been called — no per-cell
            // storage needed, since this whole zone is claimed atomically.
            return ownerAgentsMinted >= OWNER_AGENTS;
        }
        return agentOwner[row][col] != address(0);
    }

    /// Returns the address that owns a given agent, or address(0) if unclaimed.
    function agentOwnerOf(uint8 row, uint16 col) external view returns (address) {
        uint256 idx = _coordsToIndex(row, col);
        if (idx < OWNER_AGENTS) {
            return ownerAgentsMinted >= OWNER_AGENTS ? allocationHolder : address(0);
        }
        return agentOwner[row][col];
    }

    // ─── OWNER MINT (30% allocation, top of the pyramid) ────────
    // The first OWNER_AGENTS (3,000) cells — the top ~54 rows of the
    // triangle — are permanently reserved for the owner. Public mints
    // can never touch this zone (see mint() below), so there is no
    // race condition regardless of when ownerMintAll() is called.
    event OwnerBatchMinted(address indexed owner, uint256 fromIndex, uint256 toIndex, uint256 count);

    // Converts (row, col) into a linear index (0-based, row-major over
    // the triangle). Row r starts at index r*r and holds (2r+1) cells.
    function _coordsToIndex(uint8 row, uint16 col) internal pure returns (uint256) {
        uint256 r = uint256(row);
        uint16 rowStart = CENTER - row;
        uint256 offset = uint256(col - rowStart);
        return r * r + offset;
    }

    function ownerMintAll() external onlyOwner nonReentrant {
        require(!mintClosed, "Mint is closed");
        require(ownerAgentsMinted == 0, "Owner allocation already claimed");

        allocationHolder = owner;
        ownerAgentsMinted = OWNER_AGENTS;
        totalAgentsMinted += OWNER_AGENTS;

        uint256 amount = TOKENS_PER_AGENT * OWNER_AGENTS;
        _totalSupply     += amount;
        _balances[owner] += amount;

        emit Transfer(address(0), owner, amount);
        emit OwnerBatchMinted(owner, 0, OWNER_AGENTS - 1, OWNER_AGENTS);

        if (totalAgentsMinted >= MAX_AGENTS) {
            mintClosed = true;
            emit MintClosed(_totalSupply);
        }
    }

    // ─── START PUBLIC MINT ──────────────────────────────────────
    /// Opens the public mint. IRREVERSIBLE: after this call, mintPrice
    /// and liquidityWallet can never be changed again.
    function startMint() external onlyOwner {
        require(!mintStarted, "Mint already started");
        require(!mintClosed,  "Mint is closed");
        mintStarted = true;
        emit MintStarted(mintPrice, liquidityWallet);
    }

    // ─── MINT ───────────────────────────────────────────────────
    function mint(uint8 row, uint16 col) external payable nonReentrant {
        require(mintStarted,                           "Mint not started");
        require(!mintClosed,                           "Mint is closed");
        require(row < ROWS,                            "Row out of bounds");
        require(col < COLS,                            "Col out of bounds");
        // Must be inside the triangle pyramid
        require(col >= CENTER - row && col <= CENTER + row, "Agent outside pyramid");
        // The top OWNER_AGENTS cells are permanently reserved for the owner
        require(_coordsToIndex(row, col) >= OWNER_AGENTS, "Reserved for owner allocation");
        require(!isAgentMinted(row, col),               "Agent already minted");
        require(totalAgentsMinted < MAX_AGENTS,          "Max agents reached");
        uint256 price = mintPrice;
        require(msg.value >= price, "Insufficient ETH");

        // Effects first: record the agent and credit the tokens
        agentOwner[row][col]        = msg.sender;
        totalAgentsMinted++;
        _totalSupply              += TOKENS_PER_AGENT;
        _balances[msg.sender]     += TOKENS_PER_AGENT;

        emit Transfer(address(0), msg.sender, TOKENS_PER_AGENT);
        emit AgentMinted(msg.sender, row, col, totalAgentsMinted);

        if (totalAgentsMinted >= MAX_AGENTS) {
            mintClosed = true;
            emit MintClosed(_totalSupply);
        }

        // Interactions last: forward the mint price to the liquidity wallet...
        (bool ok,) = payable(liquidityWallet).call{value: price}("");
        require(ok, "Transfer to liquidity failed");
        // ...and refund any excess ETH
        if (msg.value > price) {
            (bool ok2,) = payable(msg.sender).call{value: msg.value - price}("");
            require(ok2, "Refund failed");
        }
    }

    // ─── MINT BATCH (up to 10 agents in one transaction) ────────
    uint256 public constant MAX_BATCH_SIZE = 10;

    function mintBatch(uint8[] calldata rows, uint16[] calldata cols) external payable nonReentrant {
        require(mintStarted, "Mint not started");
        require(!mintClosed, "Mint is closed");
        uint256 n = rows.length;
        require(n > 0 && n <= MAX_BATCH_SIZE, "Batch size must be 1-10");
        require(cols.length == n, "Rows/cols length mismatch");
        require(totalAgentsMinted + n <= MAX_AGENTS, "Not enough agents left");

        uint256 price = mintPrice;
        uint256 totalCost = price * n;
        require(msg.value >= totalCost, "Insufficient ETH");

        for (uint256 i = 0; i < n; i++) {
            uint8 row = rows[i];
            uint16 col = cols[i];
            require(row < ROWS, "Row out of bounds");
            require(col < COLS, "Col out of bounds");
            require(col >= CENTER - row && col <= CENTER + row, "Agent outside pyramid");
            require(_coordsToIndex(row, col) >= OWNER_AGENTS, "Reserved for owner allocation");
            require(!isAgentMinted(row, col), "Agent already minted");

            agentOwner[row][col] = msg.sender;
            totalAgentsMinted++;
            emit AgentMinted(msg.sender, row, col, totalAgentsMinted);
        }

        // Effects first: credit the tokens
        uint256 amount = TOKENS_PER_AGENT * n;
        _totalSupply          += amount;
        _balances[msg.sender] += amount;
        emit Transfer(address(0), msg.sender, amount);

        if (totalAgentsMinted >= MAX_AGENTS) {
            mintClosed = true;
            emit MintClosed(_totalSupply);
        }

        // Interactions last: forward the total cost to the liquidity wallet...
        (bool ok,) = payable(liquidityWallet).call{value: totalCost}("");
        require(ok, "Transfer to liquidity failed");
        // ...and refund any excess ETH
        if (msg.value > totalCost) {
            (bool ok2,) = payable(msg.sender).call{value: msg.value - totalCost}("");
            require(ok2, "Refund failed");
        }
    }

    /// Withdraw any leftover ETH (only possible through a forced send, e.g. selfdestruct:
    /// the contract has no receive() and normal transfers to it revert)
    function withdraw() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "Nothing to withdraw");
        (bool ok,) = payable(liquidityWallet).call{value: bal}("");
        require(ok, "Withdraw failed");
        emit Withdrawn(liquidityWallet, bal);
    }

    /// Adjust mint price — only BEFORE startMint(), and capped at MAX_MINT_PRICE
    function setMintPrice(uint256 newPrice) external onlyOwner {
        require(!mintStarted, "Price locked: mint started");
        require(newPrice > 0 && newPrice <= MAX_MINT_PRICE, "Price out of range");
        mintPrice = newPrice;
        emit PriceUpdated(newPrice);
    }

    /// Update liquidity wallet address — only BEFORE startMint()
    function setLiquidityWallet(address newWallet) external onlyOwner {
        require(!mintStarted, "Wallet locked: mint started");
        require(newWallet != address(0), "Invalid address");
        liquidityWallet = newWallet;
        emit LiquidityWalletUpdated(newWallet);
    }

    /// Transfer ownership to a new address
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// Renounce ownership permanently — only once the mint is closed (sold out or closed by the owner).
    /// This guarantees startMint() and ownerMintAll() have been dealt with before the owner powers disappear.
    /// WARNING: irreversible — no one will be able to call owner functions after this
    function renounceOwnership() external onlyOwner {
        require(mintClosed, "Mint not complete");
        emit OwnershipRenounced(owner);
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    /// Emergency stop — owner can close mint manually if needed
    function closeMint() external onlyOwner {
        mintClosed = true;
        emit MintClosed(_totalSupply);
    }

    // ─── ERC20 ──────────────────────────────────────────────────
    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address a) external view override returns (uint256) { return _balances[a]; }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(to != address(0), "Zero address");
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to]         += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address o, address s) external view override returns (uint256) {
        return _allowances[o][s];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        require(spender != address(0), "Zero address");
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(to != address(0), "Zero address");
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to]   += amount;
        emit Transfer(from, to, amount);
        return true;
    }

}