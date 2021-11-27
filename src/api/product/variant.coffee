import * as Obj from "@dashkite/joy/object"
import * as Meta from "@dashkite/joy/metaclass"
import * as Shopify from "../../shopify"
import { getStore } from "../../stores"
import { meta } from "../helpers"

class ProductVariant

  @from: (store, data) ->
    Object.assign new ProductVariant,
      store: store
      _: data

  @get: (store, id) ->
    self = Object.assign new ProductVariant, { store, _: { id } }
    self.get()

  @list: (store, id) ->
    { variants } = await Shopify.get store, "/products/#{id}/variants.json?limit=250"
    for variant in variants
      Object.assign new ProductVariant,
        store: store
        _: variant

  # TODO replace this nonsense with forward pointers

  @getFromInventoryItem: (store, id) ->
    { variants } = await Shopify.get store, "/variants.json"
    for variant in variants when variant.inventory_item_id == id
      return ProductVariant.from store, variant

  Meta.mixin @::, [
    Meta.getters
      id: -> @_.id
      sku: -> @_.sku
      image_id: -> @_.image_id
      inventory: ->
        # make sure we have the latest
        await @get()
        @_.inventory_quantity

    Meta.setters
      image_id: (value) -> @_.image_id = value
  ]

  sync: ->
    { vendor, id } = await @mget "reseller"
    resellerStore = getStore vendor
    resellerVariant = await ProductVariant.get resellerStore, id
    resellerVariant.setInventory await @getInventory()
    
  setInventory: (value) ->
    { inventory_levels } = await Shopify.get @store,
      "/inventory_levels.json?inventory_item_ids=#{@_.inventory_item_id}"
    Shopify.post @store, "/inventory_levels/set.json",
      location_id: inventory_levels[0].location_id
      inventory_item_id: @_.inventory_item_id
      available: value

  getInventory: ->
    { inventory_levels } = await Shopify.get @store, 
      "/inventory_levels.json?inventory_item_ids=#{@_.inventory_item_id}"
    total = 0
    for { available } in inventory_levels
      total += available
    total

  get: ->
    @_ = Obj.get "variant", 
      await Shopify.get @store, "/variants/#{@_.id}.json"
    @

  put: ->
    @_ = Obj.get "product", 
      await Shopify.put @store,
        "/variants/#{@_.id}.json",
        variant: Obj.exclude [
          "title"
          "position"
          "presentment_prices"
          "created_at"
          "updated_at"
          "admin_graphql_api_id"
          "inventory_quantity"
          "inventory_quantity_adjustment"
          "inventory_item_id"
          "old_inventory_quantity"
        ], @_
    @

  _mget: (name) ->
    { metafields } = await Shopify.get @store,
        "/products/#{@_.product_id}/variants/#{@_.id}/metafields.json"
    for field in metafields
      if ( "dashkite" == field.namespace ) && ( name == field.key )
        return field
    # if not found...
    undefined

  mget: (name) ->
    metafield = await @_mget name
    if metafield?
      return JSON.parse metafield.value
    undefined

  mset: (name, value) ->
    Shopify.post @store, "/products/#{@_.product_id}/variants/#{@_.id}/metafields.json",
      metafield: meta name, value

  mdelete: (name) ->
    metafield = await @_mget name
    if metafield?
      await Shopify.del @store, "/metafields/#{metafield.id}.json",
    undefined

export {
  ProductVariant
}
