// File: contracts/marketplace/Marketplace.sol
pragma solidity ^0.5.5;

import "../openzeppelin/ownership/Ownable.sol";
import "../openzeppelin/lifecycle/Pausable.sol";
import "../openzeppelin/math/SafeMath.sol";
import "../openzeppelin/AddressUtils.sol";
import "../openzeppelin/migrations/Migratable.sol";

import "./MarketplaceStorage.sol";

contract Marketplace is Migratable, Ownable, Pausable, MarketplaceStorage {
  using SafeMath for uint256;
  using AddressUtils for address;

  /**
    * @dev Sets the publication fee that's charged to users to publish items
    * @param _publicationFee - Fee amount in wei this contract charges to publish an item
    */
  function setPublicationFee(uint256 _publicationFee) external onlyOwner {
    publicationFeeInWei = _publicationFee;
    emit ChangedPublicationFee(publicationFeeInWei);
  }

  /**
    * @dev Sets the share cut for the owner of the contract that's
    *  charged to the seller on a successful sale
    * @param _ownerCutPerMillion - Share amount, from 0 to 999,999
    */
  function setOwnerCutPerMillion(uint256 _ownerCutPerMillion) external onlyOwner {
    require(_ownerCutPerMillion < 1000000, "The owner cut should be between 0 and 999,999");

    ownerCutPerMillion = _ownerCutPerMillion;
    emit ChangedOwnerCutPerMillion(ownerCutPerMillion);
  }

  /**
    * @dev Sets the legacy NFT address to be used
    * @param _legacyNFTAddress - Address of the NFT address used for legacy methods that don't have nftAddress as parameter
    */
  function setLegacyNFTAddress(address _legacyNFTAddress) external onlyOwner {
    _requireERC721(_legacyNFTAddress);

    legacyNFTAddress = _legacyNFTAddress;
    emit ChangeLegacyNFTAddress(legacyNFTAddress);
  }

  /**
    * @dev Initialize this contract. Acts as a constructor
    * @param _acceptedToken - Address of the ERC20 accepted for this marketplace
    * @param _legacyNFTAddress - Address of the NFT address used for legacy methods that don't have nftAddress as parameter
    */
  function initialize(
    address _acceptedToken,
    address _legacyNFTAddress,
    address _owner
  )
    public
    isInitializer("Marketplace", "0.0.1")
  {

    // msg.sender is the App contract not the real owner. Calls ownable behind the scenes...sigh
    require(_owner != address(0), "Invalid owner");
    Pausable.initialize(_owner);

    require(_acceptedToken.isContract(), "The accepted token address must be a deployed contract");
    acceptedToken = ERC20Interface(_acceptedToken);

    _requireERC721(_legacyNFTAddress);
    legacyNFTAddress = _legacyNFTAddress;
  }

  /**
    * @dev Creates a new order
    * @param nftAddress - Non fungible registry address
    * @param assetId - ID of the published NFT
    * @param priceInWei - Price in Wei for the supported coin
    * @param expiresAt - Duration of the order (in hours)
    */
  function createOrder(
    address nftAddress,
    uint256 assetId,
    uint256 priceInWei,
    uint256 expiresAt
  )
    public
    whenNotPaused
  {
    _createOrder(
      nftAddress,
      assetId,
      priceInWei,
      expiresAt
    );
  }

  /**
    * @dev [LEGACY] Creates a new order
    * @param assetId - ID of the published NFT
    * @param priceInWei - Price in Wei for the supported coin
    * @param expiresAt - Duration of the order (in hours)
    */
  function createOrder(
    uint256 assetId,
    uint256 priceInWei,
    uint256 expiresAt
  )
    public
    whenNotPaused
  {
    _createOrder(
      legacyNFTAddress,
      assetId,
      priceInWei,
      expiresAt
    );

    Order memory order = orderByAssetId[legacyNFTAddress][assetId];
    emit AuctionCreated(
      order.id,
      assetId,
      order.seller,
      order.price,
      order.expiresAt
    );
  }

  /**
    * @dev Cancel an already published order
    *  can only be canceled by seller or the contract owner
    * @param nftAddress - Address of the NFT registry
    * @param assetId - ID of the published NFT
    */
  function cancelOrder(address nftAddress, uint256 assetId) public whenNotPaused {
    _cancelOrder(nftAddress, assetId);
  }

  /**
    * @dev [LEGACY] Cancel an already published order
    *  can only be canceled by seller or the contract owner
    * @param assetId - ID of the published NFT
    */
  function cancelOrder(uint256 assetId) public whenNotPaused {
    Order memory order = _cancelOrder(legacyNFTAddress, assetId);

    emit AuctionCancelled(
      order.id,
      assetId,
      order.seller
    );
  }

  /**
    * @dev Executes the sale for a published NFT and checks for the asset fingerprint
    * @param nftAddress - Address of the NFT registry
    * @param assetId - ID of the published NFT
    * @param price - Order price
    * @param fingerprint - Verification info for the asset
    */
  function safeExecuteOrder(
    address nftAddress,
    uint256 assetId,
    uint256 price,
    bytes memory fingerprint
  )
   public
   whenNotPaused
  {
    _executeOrder(
      nftAddress,
      assetId,
      price,
      fingerprint
    );
  }

  /**
    * @dev Executes the sale for a published NFT
    * @param nftAddress - Address of the NFT registry
    * @param assetId - ID of the published NFT
    * @param price - Order price
    */
  function executeOrder(
    address nftAddress,
    uint256 assetId,
    uint256 price
  )
   public
   whenNotPaused
  {
    _executeOrder(
      nftAddress,
      assetId,
      price,
      ""
    );
  }

  /**
    * @dev [LEGACY] Executes the sale for a published NFT
    * @param assetId - ID of the published NFT
    * @param price - Order price
    */
  function executeOrder(
    uint256 assetId,
    uint256 price
  )
   public
   whenNotPaused
  {
    Order memory order = _executeOrder(
      legacyNFTAddress,
      assetId,
      price,
      ""
    );

    emit AuctionSuccessful(
      order.id,
      assetId,
      order.seller,
      price,
      msg.sender
    );
  }

  /**
    * @dev [LEGACY] Gets an order using the legacy NFT address.
    * @dev It's equivalent to orderByAssetId[legacyNFTAddress][assetId] but returns same structure as the old Auction
    * @param assetId - ID of the published NFT
    */
  function auctionByAssetId(
    uint256 assetId
  )
    public
    view
    returns
    (bytes32, address, uint256, uint256)
  {
    Order memory order = orderByAssetId[legacyNFTAddress][assetId];
    return (order.id, order.seller, order.price, order.expiresAt);
  }

  /**
    * @dev Creates a new order
    * @param nftAddress - Non fungible registry address
    * @param assetId - ID of the published NFT
    * @param priceInWei - Price in Wei for the supported coin
    * @param expiresAt - Duration of the order (in hours)
    */
  function _createOrder(
    address nftAddress,
    uint256 assetId,
    uint256 priceInWei,
    uint256 expiresAt
  )
    internal
  {
    _requireERC721(nftAddress);

    ERC721Interface nftRegistry = ERC721Interface(nftAddress);
    address assetOwner = nftRegistry.ownerOf(assetId);

    require(msg.sender == assetOwner, "Only the owner can create orders");
    require(
      nftRegistry.getApproved(assetId) == address(this) || nftRegistry.isApprovedForAll(assetOwner, address(this)),
      "The contract is not authorized to manage the asset"
    );
    require(priceInWei > 0, "Price should be bigger than 0");
    require(expiresAt > block.timestamp.add(1 minutes), "Publication should be more than 1 minute in the future");

    bytes32 orderId = keccak256(
      abi.encodePacked(
        block.timestamp,
        assetOwner,
        assetId,
        nftAddress,
        priceInWei
      )
    );

    orderByAssetId[nftAddress][assetId] = Order({
      id: orderId,
      seller: assetOwner,
      nftAddress: nftAddress,
      price: priceInWei,
      expiresAt: expiresAt
    });

    // Check if there's a publication fee and
    // transfer the amount to marketplace owner
    if (publicationFeeInWei > 0) {
      require(
        acceptedToken.transferFrom(msg.sender, owner, publicationFeeInWei),
        "Transfering the publication fee to the Marketplace owner failed"
      );
    }

    emit OrderCreated(
      orderId,
      assetId,
      assetOwner,
      nftAddress,
      priceInWei,
      expiresAt
    );
  }

  /**
    * @dev Cancel an already published order
    *  can only be canceled by seller or the contract owner
    * @param nftAddress - Address of the NFT registry
    * @param assetId - ID of the published NFT
    */
  function _cancelOrder(address nftAddress, uint256 assetId) internal returns (Order memory) {
    Order memory order = orderByAssetId[nftAddress][assetId];

    require(order.id != 0, "Asset not published");
    require(order.seller == msg.sender || msg.sender == owner, "Unauthorized user");

    bytes32 orderId = order.id;
    address orderSeller = order.seller;
    address orderNftAddress = order.nftAddress;
    delete orderByAssetId[nftAddress][assetId];

    emit OrderCancelled(
      orderId,
      assetId,
      orderSeller,
      orderNftAddress
    );

    return order;
  }

  /**
    * @dev Executes the sale for a published NFT
    * @param nftAddress - Address of the NFT registry
    * @param assetId - ID of the published NFT
    * @param price - Order price
    * @param fingerprint - Verification info for the asset
    */
  function _executeOrder(
    address nftAddress,
    uint256 assetId,
    uint256 price,
    bytes memory fingerprint
  )
   internal returns (Order memory)
  {
    _requireERC721(nftAddress);

    ERC721Verifiable nftRegistry = ERC721Verifiable(nftAddress);

    if (nftRegistry.supportsInterface(InterfaceId_ValidateFingerprint)) {
      require(
        nftRegistry.verifyFingerprint(assetId, fingerprint),
        "The asset fingerprint is not valid"
      );
    }
    Order memory order = orderByAssetId[nftAddress][assetId];

    require(order.id != 0, "Asset not published");

    address seller = order.seller;

    require(seller != address(0), "Invalid address");
    require(seller != msg.sender, "Unauthorized user");
    require(order.price == price, "The price is not correct");
    require(block.timestamp < order.expiresAt, "The order expired");
    require(seller == nftRegistry.ownerOf(assetId), "The seller is no longer the owner");

    uint saleShareAmount = 0;

    bytes32 orderId = order.id;
    delete orderByAssetId[nftAddress][assetId];

    if (ownerCutPerMillion > 0) {
      // Calculate sale share
      saleShareAmount = price.mul(ownerCutPerMillion).div(1000000);

      // Transfer share amount for marketplace Owner
      require(
        acceptedToken.transferFrom(msg.sender, owner, saleShareAmount),
        "Transfering the cut to the Marketplace owner failed"
      );
    }

    // Transfer sale amount to seller
    require(
      acceptedToken.transferFrom(msg.sender, seller, price.sub(saleShareAmount)),
      "Transfering the sale amount to the seller failed"
    );

    // Transfer asset owner
    nftRegistry.safeTransferFrom(
      seller,
      msg.sender,
      assetId
    );

    emit OrderSuccessful(
      orderId,
      assetId,
      seller,
      nftAddress,
      price,
      msg.sender
    );

    return order;
  }

  function _requireERC721(address nftAddress) internal view {
    require(nftAddress.isContract(), "The NFT Address should be a contract");

    ERC721Interface nftRegistry = ERC721Interface(nftAddress);
    require(
      nftRegistry.supportsInterface(ERC721_Interface),
      "The NFT contract has an invalid ERC721 implementation"
    );
  }
}