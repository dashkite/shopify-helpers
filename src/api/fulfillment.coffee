import * as Obj from "@dashkite/joy/object"
import * as Meta from "@dashkite/joy/metaclass"
import * as Shopify from "../shopify"
import { Shop } from "./shop"

class Fulfillment

  @from: (store, data) ->
    Object.assign new Fulfillment,
      store: store
      _: data    

  @create: (order, fulfillment) ->
    body =
      service: fulfillment?.service
      status: fulfillment?.status 
      location_id: order.locationID ? ( await Shop.getPrimaryLocationID order.store )
      tracking_company: fulfillment?.trackingCompany
      tracking_number: fulfillment?.trackingNumber
      tracking_urls: fulfillment?.trackingURLs
      
    body.line_items = fulfillment.lineItems if fulfillment?.lineItems?

    Object.assign new Fulfillment,
      store: order.store
      _: Obj.get "fulfillment",
        await Shopify.post order.store, "/orders/#{order.id}/fulfillments.json",
          fulfillment: body
            
            

  @list: (order) ->
    { fulfillments } = await Shopify.get order.store, 
      "/orders/#{order.id}/fulfillments.json"
    
    for fulfillment in fulfillments
      Object.assign new Fulfillment,
        store: order.store
        _: fulfillment

  @get: (store, { order_id, id }) ->
    self = Object.assign new Fulfillment, 
      { store, _: { id, order_id } }

    self.get()

  Meta.mixin @::, [
    Meta.getters
      id: -> @_.id
      service: -> @_.service
      orderID: -> @_.order_id
      orderURL: -> "https://#{@store.subdomain}.myshopify.com/admin/orders/#{@orderID}"
      trackingCompany: -> @_.tracking_company
      trackingNumber: -> @_.tracking_number
      trackingURLs: -> @_.tracking_urls
      status: -> @_.status

    Meta.setters
      status: -> @_.status
      trackingNumber: -> @_.tracking_number
      trackingCompany: -> @_.tracking_company
      trackingURLs: -> @_.tracking_urls
  ]

  get: ->
    @_ = Obj.get "fulfillment",
      await Shopify.get @store, 
        "/orders/#{@orderID}/fulfillments/#{@id}.json"
    @

  put: ->
    @_ = Obj.get "fulfillment", 
      await Shopify.put @store, 
        "/orders/#{@orderID}/fulfillments/#{@id}.json", 
        fulfillment:
          tracking_number: @trackingNumber
          tracking_company: @trackingCompany
          tracking_urls: @trackingURLs
    @

  complete: ->
    @_ = Obj.get "fulfillment", 
      await Shopify.post @store, 
        "/orders/#{@orderID}/fulfillments/#{@id}/complete.json"
    @


        
export {
  Fulfillment
}
