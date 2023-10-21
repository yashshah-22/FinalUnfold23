// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC4337Wallet {
    function createAccount() external returns (address);
    function deposit() external payable;
    function withdraw(address recipient, uint256 amount) external;
    // function executeUserOperation(UserOperation calldata userOp) external;\
    function login(string calldata username, string calldata password ) external returns (bool) ;
}

interface IUniswapV2{
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}


contract ERC4337Wallet is IERC4337Wallet, ERC165, ERC165Storage, ERC721, Ownable {
    mapping(address => uint256) public balances;
    mapping(string => address) public usernames;
    mapping(string => bytes32) public passwordHashes;
    mapping(address => bool) public isKYCed;
    uint256 public totalTokensMinted;
    address private uniswapAddress;
    address public  taxAddress;


    constructor() ERC721("SoulBoundKYC", "SBTKYC") Ownable(msg.sender) {
        // Register the ERC-4337 interface ID.
        _registerInterface(0x7b22e282);
        // uniswapAddress = _uniswap;
    }

    // Get the Uniswap router contract address.
    address routerAddress = 0x7A250d5630b4cF539739dF2C5daCb4C394553b81;

    // Create a new Uniswap router contract object.
    IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);

    // Events
    event loginResult(string loginStatus);
    event kycStatus(bool kycState);
    event transactionStatus(string status);


    function supportsInterface(bytes4 interfaceId) public view override(ERC165, ERC165Storage, ERC721) returns (bool) {
    // Your implementation here to handle the supported interfaces
    }

    function createAccount() external override returns (address) {
        // Generate a new random address for the account.
        // Wallet newWallet = new Wallet(msg.sender);

        address newAccount = address(uint160(uint(keccak256(abi.encodePacked(msg.sender, block.timestamp)))));

        // Set the balance of the new account to zero.
        balances[newAccount] = 0;

        // Return the address of the new account.
        return newAccount;
        // emit  AccountCreated(newAccount);/
    }

    function deposit() external override payable {
        // Increase the balance of the current account by the amount of ETH sent.
        balances[msg.sender] += msg.value;
    }

    function withdraw(address recipient, uint256 amount) external override {
        // Check that the current account has enough balance to withdraw.
        require(balances[msg.sender] >= amount);

        // Decrease the balance of the current account by the amount withdrawn.
        balances[msg.sender] -= amount;

        // Send the withdrawn ETH to the recipient.
        payable(recipient).transfer(amount);
    }

    function isRegistered(string calldata username, string calldata password) external returns (uint) {
        // Check if the user is already registered.
        bool isRegisteredBool = usernames[username] != address(0);

        // If the user is already registered, check if the credentials match.
        if (isRegisteredBool) {
            // Get the password hash for the username.
            bytes32 passwordHash = passwordHashes[username];

            // Hash the input password.
            bytes32 inputPasswordHash = keccak256(abi.encodePacked(password));

            // Check if the password hashes match.
            if (inputPasswordHash == passwordHash) {
                // The credentials match.

                emit loginResult("existing_user");
                return 1;
            }
            else {
                emit loginResult("login_failed");
                return 2;
            }
        }

        // The credentials do not match.
        return 0;
    }

    function login(string calldata username, string calldata password) external returns (bool)  {
        // Check if the user is already registered.
        uint isRegisteredBool = this.isRegistered(username, password);

        // If the user is not already registered, create a new account for them and mark them as registered.
        if (isRegisteredBool == 0) {
            // Create a new account for the user.
            address accountAddress = this.createAccount();

            // Mark the user as registered by associating their username with their account address.
            usernames[username] = accountAddress;

            // Generate a password hash for the user and store it.
            passwordHashes[username] = keccak256(abi.encodePacked(password));

            emit loginResult("new_account_created");
        }

        // Return true if the user is registered.
        return true;
    }

    function isKYCd(address userAddress) public returns (bool) {
        emit kycStatus(isKYCed[userAddress]);
        return isKYCed[userAddress];
    }

    function mintKYCSBT(address userAddress) public onlyOwner {
        require(!isKYCed[userAddress], "User is already KYCed");

        uint256 tokenId = totalTokensMinted++;
        _mint(userAddress, tokenId);
        isKYCed[userAddress] = true;
    }

    function getBalance(address tokenAddress, address account) public view returns (uint256) {
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(account);
    }

    function sendERC20Tokens(address tokenAddress, address recipientAddress, uint256 amount ) public returns(bool) {
            // Create an instance of the IERC20 interface for the token we want to send.
            IERC20 token = IERC20(tokenAddress);

            // Transfer the tokens to the recipient.
            token.transfer(recipientAddress, amount);

            return true;
        }

    // Buy function
    function buy(uint256 amountIn, uint256 amountOutMin, address fromAsset, address toAsset) public onlyOwner returns(bool)  {
       
       require(this.getBalance(fromAsset, msg.sender) > amountIn , "Insufficient Balance");

        //Tax collection per transaction
        uint256 taxCollected = amountIn / 100;
        this.sendERC20Tokens(fromAsset, taxAddress, taxCollected);

        // Define the token swap path.
        address[] memory path = new address[](2);
        path[0] = fromAsset;
        path[1] = toAsset;

        // Swap tokens
        router.swapExactTokensForTokens(
            amountIn - taxCollected, //100 * 10**18, // amountIn
            amountOutMin, //0, // amountOutMin
            path,
            msg.sender, // to
            block.timestamp + 300 // deadline
        );

        emit transactionStatus("Token bought and tax deducted");
        return true;
    }


}