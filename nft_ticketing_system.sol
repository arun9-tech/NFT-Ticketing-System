// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTTicketingSystem is ERC721, Ownable {
    uint256 private _tokenIdCounter;

    struct Event {
        string name;
        uint256 price;
        uint256 maxTickets;
        uint256 ticketsSold;
        uint256 eventDate;
        bool isActive;
    }

    struct Ticket {
        uint256 eventId;
        address ticketOwner;
        bool isUsed;
        uint256 purchaseDate;
    }

    mapping(uint256 => Event) public events;
    mapping(uint256 => Ticket) public tickets;
    mapping(uint256 => mapping(address => uint256)) public ticketsPerEventPerUser;
    
    uint256 public eventCounter;
    uint256 public constant MAX_TICKETS_PER_USER = 5;

    event EventCreated(uint256 indexed eventId, string name, uint256 price, uint256 maxTickets);
    event TicketPurchased(uint256 indexed tokenId, uint256 indexed eventId, address indexed buyer);
    event TicketUsed(uint256 indexed tokenId, uint256 indexed eventId);

    constructor() ERC721("NFT Ticket", "TICKET") Ownable(msg.sender) {}

    /**
     * @dev Creates a new event (only owner can create events)
     * @param _name Name of the event
     * @param _price Price per ticket in wei
     * @param _maxTickets Maximum number of tickets available
     * @param _eventDate Event date as timestamp
     */
    function createEvent(
        string memory _name,
        uint256 _price,
        uint256 _maxTickets,
        uint256 _eventDate
    ) external onlyOwner {
        require(bytes(_name).length > 0, "Event name cannot be empty");
        require(_price > 0, "Price must be greater than 0");
        require(_maxTickets > 0, "Max tickets must be greater than 0");
        require(_eventDate > block.timestamp, "Event date must be in the future");

        events[eventCounter] = Event({
            name: _name,
            price: _price,
            maxTickets: _maxTickets,
            ticketsSold: 0,
            eventDate: _eventDate,
            isActive: true
        });

        emit EventCreated(eventCounter, _name, _price, _maxTickets);
        eventCounter++;
    }

    /**
     * @dev Purchase tickets for a specific event
     * @param _eventId ID of the event
     * @param _quantity Number of tickets to purchase
     */
    function purchaseTickets(uint256 _eventId, uint256 _quantity) external payable {
        Event storage eventInfo = events[_eventId];
        
        require(eventInfo.isActive, "Event is not active");
        require(_quantity > 0, "Quantity must be greater than 0");
        require(_quantity <= MAX_TICKETS_PER_USER, "Cannot purchase more than 5 tickets at once");
        require(
            ticketsPerEventPerUser[_eventId][msg.sender] + _quantity <= MAX_TICKETS_PER_USER,
            "Cannot exceed maximum tickets per user"
        );
        require(
            eventInfo.ticketsSold + _quantity <= eventInfo.maxTickets,
            "Not enough tickets available"
        );
        require(msg.value == eventInfo.price * _quantity, "Incorrect payment amount");
        require(block.timestamp < eventInfo.eventDate, "Event has already occurred");

        for (uint256 i = 0; i < _quantity; i++) {
            uint256 tokenId = _tokenIdCounter;
            _tokenIdCounter++;
            
            tickets[tokenId] = Ticket({
                eventId: _eventId,
                ticketOwner: msg.sender,
                isUsed: false,
                purchaseDate: block.timestamp
            });

            _safeMint(msg.sender, tokenId);
            emit TicketPurchased(tokenId, _eventId, msg.sender);
        }

        eventInfo.ticketsSold += _quantity;
        ticketsPerEventPerUser[_eventId][msg.sender] += _quantity;
    }

    /**
     * @dev Use a ticket for event entry (only owner can validate tickets)
     * @param _tokenId ID of the ticket NFT
     */
    function useTicket(uint256 _tokenId) external onlyOwner {
        require(_tokenIdCounter > _tokenId, "Ticket does not exist");
        require(ownerOf(_tokenId) != address(0), "Ticket does not exist");
        
        Ticket storage ticket = tickets[_tokenId];
        Event storage eventInfo = events[ticket.eventId];
        
        require(!ticket.isUsed, "Ticket has already been used");
        require(eventInfo.isActive, "Event is not active");
        require(
            block.timestamp >= eventInfo.eventDate - 2 hours && 
            block.timestamp <= eventInfo.eventDate + 6 hours,
            "Ticket can only be used within event timeframe"
        );

        ticket.isUsed = true;
        emit TicketUsed(_tokenId, ticket.eventId);
    }

    // View functions
    function getEvent(uint256 _eventId) external view returns (Event memory) {
        return events[_eventId];
    }

    function getTicket(uint256 _tokenId) external view returns (Ticket memory) {
        require(_tokenIdCounter > _tokenId, "Ticket does not exist");
        return tickets[_tokenId];
    }

    function getUserTicketCount(uint256 _eventId, address _user) external view returns (uint256) {
        return ticketsPerEventPerUser[_eventId][_user];
    }

    function isTicketValid(uint256 _tokenId) external view returns (bool) {
        if (_tokenIdCounter <= _tokenId) {
            return false;
        }
        
        try this.ownerOf(_tokenId) returns (address) {
            Ticket memory ticket = tickets[_tokenId];
            Event memory eventInfo = events[ticket.eventId];
            return !ticket.isUsed && eventInfo.isActive && block.timestamp < eventInfo.eventDate;
        } catch {
            return false;
        }
    }

    // Owner functions
    function toggleEventStatus(uint256 _eventId) external onlyOwner {
        require(_eventId < eventCounter, "Event does not exist");
        events[_eventId].isActive = !events[_eventId].isActive;
    }

    function withdrawFunds() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    function totalSupply() external view returns (uint256) {
        return _tokenIdCounter;
    }

    // Override required functions
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        address previousOwner = super._update(to, tokenId, auth);
        
        // Update ticket owner when transferred
        if (from != address(0) && to != address(0)) {
            tickets[tokenId].ticketOwner = to;
        }
        
        return previousOwner;
    }
}
