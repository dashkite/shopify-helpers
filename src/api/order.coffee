import * as Obj from "@dashkite/joy/object"
import * as Meta from "@dashkite/joy/metaclass"
import { getStore } from "../stores"
import * as Shopify from "../shopify"
import { meta } from "./helpers"
import { ProductVariant } from "./product"
import { Fulfillment } from "./fulfillment"

# TODO: Further work should involve creating formal classes for parts of an order
#       like shipping address and line item.


requiresShipping = (item) -> item.requiresShipping == true

class Order

  @from: (store, data) ->
    Object.assign new Order,
      store: store
      _: data

  @create: (store, order) ->
    Object.assign new Order,
      store: store
      _: Obj.get "order",
        await Shopify.post store, "/orders.json",
          order:
            note: order.note
            note_attributes: order.noteAttributes
            shipping_address: order.shippingAddress
            line_items: do ->
              for item in order.items
                variant_id: item.variant.id
                variant_title: item.variant.title
                price: item.variant.price
                quantity: item.quantity
                requires_shipping: item.requiresShipping

  # Shopify treats this PUT as a PATCH on a limited subset of order attributes.
  @patch: (store, order) ->
    body = id: order.id
    body.note = note if order.note?
    body.note_attributes = order.noteAttributes if order.noteAttributes?
    body.shipping_address = order.shippingAddress if order.shippingAddress?

    await Shopify.put store, "/orders/#{order.id}.json", order: body
    undefined

  @cancel: (store, order) ->


  @list: (store) ->
    { orders } = await Shopify.get store, "/orders.json?status=any&limit=250"
    for order in orders
      Object.assign new Order,
        store: store
        _: order

  @get: (store, id) ->
    self = Object.assign new Order, { store, _: { id } }
    self.get()

  Meta.mixin @::, [
    Meta.getters
      id: -> @_.id
      lineItems: -> @_.line_items
      fulfillments: -> @_.fulfillments
      note: -> @_.note
      noteAttributes: -> @_.note_attributes 
      shippingAddress: -> @_.shipping_address
      locationID: -> @_.location_id
      fulfillmentStatus: -> @_.fulfillment_status
      subdomain: -> @store.subdomain
      url: -> "https://#{@subdomain}.myshopify.com/admin/orders/#{@id}"
  ]

  get: ->
    @_ = Obj.get "order",
      await Shopify.get @store, "/orders/#{@id}.json"
    @

  put: ->
    @_ = Obj.get "order", await Shopify.put @store, "/orders/#{@_.id}.json", { order: @_ }
    @

  delete: ->
    await Shopify.del @store, "/orders/#{@id}.json"
    @deleted = true
    @

  mget: (name) ->
    { metafields } = await Shopify.get @store,
      "/orders/#{@id}/metafields.json"
    for field in metafields
      if "dashkite" == field.namespace && name == field.key
        return JSON.parse field.value
    # if not found...
    undefined

  mset: (name, value) ->
    Shopify.post @store, "/orders/#{@id}/metafields.json",
      metafield: meta name, value

  # Forward line items from the paid reseller order to relevant supplier(s).
  forward: ->
    suborders = {}
    for item in @lineItems
      resellerVariant = await ProductVariant.get @store, item.variant_id
      source = await resellerVariant.mget "source"

      # Only collate suborders from line items we've indexed against suppliers
      if source?
        supplierStore = getStore source.vendor
        supplierVariant = await ProductVariant.get supplierStore, source.id
        suborders[ supplierStore.name ] ?= 
          store: supplierStore
          note: @note
          noteAttributes: @noteAttributes
          items: []

        suborders[ supplierStore.name ].items.push
          variant: supplierVariant
          quantity: item.quantity
          requiresShipping: item.requires_shipping


    # Add shipping address to only suborders that require shipping.
    for storeName, suborder of suborders
      if ( suborder.items.find requiresShipping )?
        suborder.shippingAddress = @shippingAddress


    # Create orders in supplier stores with back pointers to the reseller.
    for storeName, suborder of suborders
      order = await Order.create ( getStore storeName ), suborder
      await order.mset "source",
        vendor: @store.name
        id: @id
      order


  # TODO: Should we index forward pointers from the reseller store to the
  #       supplier store for updates and cancellation?
  forwardUpdate: ->
  forwardCancel: ->
  

  close: -> Shopify.post @store, "/orders/#{@id}/close.json"

  getFulfillmentFromTrackingNumber: (trackingNumber) ->
    for fulfillment in @fulfillments when fulfillment.tracking_number == trackingNumber
      return fulfillment
    # When we fail to match...
    undefined

  listFulfillments: -> Fulfillment.list @

  createForwardFulfillment: (supplierFulfillment) ->
    source = await @mget "source"
    if !source?
      # This supplier order is not one associated with DashKite.
      return

    { vendor, id } = source
    resellerStore = getStore vendor
    resellerOrder = await Order.get resellerStore, id

    resellerFulfillment = await Fulfillment.create resellerOrder, supplierFulfillment
    await resellerOrder.mset "fulfillment:#{supplierFulfillment.id}",
      id: resellerFulfillment.id
      order_id: resellerOrder.id

    resellerFulfillment

  updateForwardFulfillment: (supplierFulfillment) ->
    source = await @mget "source"
    if !source?
      # This supplier order is not one associated with DashKite.
      return

    { vendor, id } = source
    resellerStore = getStore vendor
    resellerOrder = await Order.get resellerStore, id

    metadata = await resellerOrder.mget "fulfillment:#{supplierFulfillment.id}"
    
    if !metadata?
      return undefined

    resellerFulfillment = await Fulfillment.get resellerStore, metadata
    Object.assign resellerFulfillment, Obj.mask [
        "trackingNumber"
        "trackingCompany"
        "trackingURLs"
      ], supplierFulfillment

    await resellerFulfillment.put()

    if supplierFulfillment.status == "fulfilled" && resellerFulfillment.status != "fulfilled"
      await resellerFulfillment.complete()
    
    resellerFulfillment
    
        
export {
  Order
}
