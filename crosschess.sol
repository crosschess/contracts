pragma solidity 0.8.4;

/**
 *Submitted for verification at Etherscan.io on 2021-01-06
*/

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract CrossChess is Ownable {
    using SafeMath for uint256;
    struct Game {
        address owner;
        address accepter;
        address token;
        uint amount;
        bool accepted;
        uint status;
        uint fee;
        uint acceptanceDeadline;
        uint decisionDeadline;
        address proposeDrawAddress;
    }
    
    struct Gamer {
        bool init;
        int rating;
        uint totalGames;
        uint totalWons;
        uint totalLoses;
        uint totalDrawns;
    }
    
    mapping(address => Gamer) public gamers;
    
    event NewGame(bytes url);
    
    event AcceptedGame(bytes url);
    
    event FinishedGame(bytes url);
    
    event CancelledGame(bytes url);
    
    uint public fee = 0.01 ether;
    
    function adjustFee(uint newFee) onlyOwner public {
        fee = newFee;
    }
    
    mapping(bytes => Game) public games;
    
    uint public acceptanceDeadline = 10000000;
    uint public decisionDeadline = 10000000;
    
    function ensureGamer() private {
        Gamer storage gamer = gamers[msg.sender];
        
        if (gamer.init == false) {
            gamer.rating = 1200;
            gamer.init = true;
        }
    }
    
    
    function getPointsForOwnerWhenHeWins(int onwerRating, int accepterRating) pure public returns(int) {
    
        int diff = (onwerRating - accepterRating) * 100;
        
        int adjustment = 0;
        
        if (diff > 0 && diff < 8000) {
            adjustment = 8;
        } else if (diff < 0 && diff > -8000) {
            adjustment = -8;
        } else if (onwerRating > accepterRating) {
            adjustment = diff / 1000;
        }
        else {
            adjustment = (diff * -1) / 1000;
        }

        return adjustment;


        
    }
    
    function changeStats(Game memory game) private {
        
        Gamer storage owner = gamers[game.owner];
        Gamer storage accepter = gamers[game.owner];
        
        owner.totalGames += 1;
        accepter.totalGames += 1;
        
        if(game.status == 1) {
            owner.totalWons += 1;
            accepter.totalLoses += 1;
        }
        
        if(game.status == 2) {
            accepter.totalWons += 1;
            owner.totalLoses += 1;
        }
        
        if (game.status == 3) {
            accepter.totalDrawns  += 1;   
            owner.totalDrawns += 1;
        }
        
        int adjustment =getPointsForOwnerWhenHeWins(owner.rating, accepter.rating);
        
        owner.rating += adjustment;
        accepter.rating += adjustment;
        //New Rating = Old Rating + k(actual points – expected points),
        
        
    } 
    
    function initGameERC20(address token, uint _amount, bytes calldata url) payable public {
        IERC20 erc20 = IERC20(token);
        
        Game storage game = games[url];
        
        require(game.amount == 0, "Should be new game");
        require(_amount > 0, "Amount should higher than 0");
        
        require(msg.value == fee, "Fee is required");
        
        payable(owner()).transfer(msg.value);
        
        game.amount = _amount;
        game.token = token;
        game.owner = msg.sender;
        game.fee = fee;
        game.acceptanceDeadline = block.timestamp + acceptanceDeadline;
        
        if (erc20.transferFrom(msg.sender, address(this), _amount)) {
            emit NewGame(url);
        }
        
        ensureGamer();
        
        
    }
    
    
    function initGameNative(bytes calldata url) payable public {
        
        
        Game storage game = games[url];
        
        require(game.amount == 0, "Should be new game");
        require(msg.value > 0, "Amount should higher than 0");
        
        uint amount = msg.value - fee; 
        
        payable(owner()).transfer(fee);
        
        game.amount = amount;
        game.token = address(0);
        game.owner = msg.sender;
        game.fee = fee;
        game.acceptanceDeadline = block.timestamp + acceptanceDeadline;
        
        ensureGamer();
        
        emit NewGame(url);
           
    }
    
    function acceptGameNative(bytes calldata url) payable public {
        Game storage game = games[url];
        
        
        require(game.amount > 0, "Should be available game");
        require(game.accepted == false, "Should be accepable game");
        require(game.amount == msg.value.sub(game.fee), "Should be same amount");
        require(game.token == address(0), "Should native token");
        require(game.acceptanceDeadline > block.timestamp , "The game deadline is reached");
        
        payable(owner()).transfer(game.fee);
        
        game.accepted = true;
        game.accepter = msg.sender;
        game.decisionDeadline = block.timestamp + decisionDeadline;
        
        ensureGamer();
        
        emit AcceptedGame(url);
    }
    
    function acceptGameERC20(address token, uint _amount, bytes calldata url) public payable {
        IERC20 erc20 = IERC20(token);
        Game storage game = games[url];
    
        require(msg.value == fee, "Fee is required");
        
        payable(owner()).transfer(msg.value);
        
        require(game.amount > 0, "Should be available game");
        require(game.accepted == false, "Should be accepable game");
        require(game.amount == _amount, "Should be same amount");
        require(game.token == token, "Should be erc20 token");
        require(game.acceptanceDeadline > block.timestamp , "The game deadline is reached");
        
        ensureGamer();
        
        if (erc20.transferFrom(msg.sender, address(this), _amount)) {
            game.accepted = true;
            game.accepter = msg.sender;
            game.decisionDeadline = block.timestamp + decisionDeadline;
            emit AcceptedGame(url);
        }
    }
    
    
    function proposeDraw(bytes calldata url) public {
        Game storage game = games[url];
        require(game.amount > 0, "Should be available game");
        require(game.accepted == true, "Should be new game");
        require(game.status == 0, "Should be game in process");
        require(game.proposeDrawAddress != msg.sender, "You can propose once");
        require(msg.sender == game.owner || msg.sender == game.accepter, "Only person who created or accepted game can propose draw");
        
        game.proposeDrawAddress = msg.sender;
    }
    
    function acceptDraw(bytes calldata url) public {
        Game storage game = games[url];
        require(game.amount > 0, "Should be available game");
        require(game.accepted == true, "Should be new game");
        require(game.status == 0, "Should be game in process");
        require(game.proposeDrawAddress != msg.sender, "You can propose once");
        
        if (game.proposeDrawAddress == game.owner) {
            require(msg.sender == game.accepter, "When onwer proposed then accepter should accept");
        }
        
        if (game.proposeDrawAddress == game.accepter) {
            require(msg.sender == game.owner, "When accepter proposed then owner should accept");
        }
        
        game.status == 3;
        
        if (game.token == address(0)) {
                payable(game.owner).transfer(game.amount);
                payable(game.accepter).transfer(game.amount);
        } else {
                IERC20 erc20 = IERC20(game.token);
                erc20.transfer(game.owner, game.amount);
                erc20.transfer(game.accepter, game.amount);
            }
        
        changeStats(game);
        
        
        emit FinishedGame(url);
    }
    
    // Cancel in case when accepter did not accept on time and acceptance deadline is reached.
    // This case is possible when user created the game but another user did not find a way to accept the game so owner should be able to withdrow money by himself
    function cancelGame(bytes calldata url) public {
        Game storage game = games[url];
        require(game.amount > 0, "Should be available game");
        require(game.accepted == false, "Should be new game");
        //require(game.acceptanceDeadline < block.timestamp  , "The game deadline is reached");
        require(game.owner == msg.sender, "Should be owner of the game");
        
        
        if (game.token == address(0)) {
            payable(game.owner).transfer(game.amount);
        } else {
            IERC20 erc20 = IERC20(game.token);
            erc20.transfer(game.owner, game.amount);
        }
        
        emit CancelledGame(url);
    }
    
    //Cancel game in case where oracle did not provide the decision on time. So the game is drawn 
    function cancelGame2(bytes calldata url) public {
        Game storage game = games[url];
        require(game.amount > 0, "Should be available game");
        require(game.accepted == true, "Should be accepted game");
        require(game.decisionDeadline < block.timestamp , "The decision deadline is reached");
        require(game.owner == msg.sender || game.accepter == msg.sender, "Should be owner of the game");
        require(game.status == 0, "Should be game in process");
        
       if (game.token == address(0)) {
            payable(game.owner).transfer(game.amount);
            payable(game.accepter).transfer(game.amount);
        } else {
            IERC20 erc20 = IERC20(game.token);
            erc20.transfer(game.owner, game.amount);
            erc20.transfer(game.accepter, game.amount);
        }
        
        emit CancelledGame(url);
    }
    
    
    //This method available for oracle only. 
    //1 when initiator won, 2 when accepter won, 3 game is drawn
    function finishGame(bytes calldata url, uint newStatus) onlyOwner public {
        Game storage game = games[url];
        require(game.amount > 0, "Should be available game");
        require(game.accepted == true, "Should be accepable game");
        require(game.status == 0, "Should be progress game");
        
        require(newStatus == 1 || newStatus == 2 || newStatus == 3, "1 when initiator won, 2 when accepter won, 3 game is drawn");
        
        game.status == newStatus;
        
        address withdrawTo = newStatus == 1 ? game.owner : game.accepter;
        
        if (newStatus == 1 || newStatus == 2) {
        
            if (game.token == address(0)) {
                payable(withdrawTo).transfer(game.amount.mul(2));
            } else {
                IERC20 erc20 = IERC20(game.token);
                erc20.transfer(withdrawTo, game.amount.mul(2));
            }
        
        }
        
        if (newStatus == 3) {
        
            if (game.token == address(0)) {
                payable(game.owner).transfer(game.amount);
                payable(game.accepter).transfer(game.amount);
            } else {
                IERC20 erc20 = IERC20(game.token);
                erc20.transfer(game.owner, game.amount);
                erc20.transfer(game.accepter, game.amount);
            }
        
        }
        
        changeStats(game);
        
        
        emit FinishedGame(url);
    } 
    
    
    
}
