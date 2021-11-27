import * as Obj from "@dashkite/joy/object"
import * as Meta from "@dashkite/joy/metaclass"
import * as Text from "@dashkite/joy/text"
import assert from "@dashkite/assert"
import { getStore } from "../stores"
import * as Shopify from "../shopify"
import { except, meta } from "./helpers"



class ProductVariant

  @from: (store, data) ->
    Object.assign new ProductVariant,
      store: store
      _: data

  @get: (store, id) ->
    self = Object.assign new ProductVariant, { store, _: { id } }
    self.get()

  @list: (store, id) ->
    variants = Obj.get "variants",
      await Shopify.get store, "/products/#{id}/variants.json?limit=250"
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
      inventory: ->
        # make sure we have the latest
        await @get()
        @_.inventory_quantity
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
    @_ = Obj.get "product", await Shopify.put @store,
      "/variants/#{@_.id}.json",
      variant: except [
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

class ProductImage

  @from: (store, data) ->
    Object.assign new ProductImage,
      store: store
      _: data

  mget: (name) ->
    { metafields } = await Shopify.get @store,
      "/metafields.json?metafield[owner_id]=#{@_.id}\
        &metafield[owner_resource]=product_image"
    for field in metafields
      if "dashkite" == field.namespace && name == field.key
        return JSON.parse field.value
    # if not found...
    undefined

  mset: (name, value) ->
    Shopify.post @store, "/metafields.json?metafield[owner_id]=#{@_.id}\
      &metafield[owner_resource]=product_image",
      metafield: meta name, value

class Product

  @create: (store, {title, html, type, status, published, tags}) ->
    Object.assign new Product,
      store: store
      _: Obj.get "product",
        await Shopify.post store, "/products.json",
          product: {
            title: title
            body_html: html
            product_type: type
            status: status ? "draft"
            published: published ? false
            tags: tags ? []
          }

  @list: (store) ->
    products = Obj.get "products", await Shopify.get store, "/products.json?limit=250"
    for product in products
      Object.assign new Product,
        store: store
        _: product

  @get: (store, id) ->
    self = Object.assign new Product, { store, _: { id } }
    self.get()

  Meta.mixin @::, [
    Meta.getters
      id: -> @_.id
      title: -> @_.title
      images: ->
        for image in @_.images
          ProductImage.from @store, image
      variants: ->
        for variant in @_.variants
          ProductVariant.from @store, variant
  ]
    
  get: ->
    @_ = Obj.get "product",
      await Shopify.get @store, "/products/#{@_.id}.json"
    @

  put: ->
    @_ = Obj.get "product", await Shopify.put @store, "/products/#{@_.id}.json", { product: @_ }
    @

  delete: ->
    await Shopify.del @store, "/products/#{@_.id}.json"
    @deleted = true
    @

  getVariantFromSKU: (sku) ->
    for variant in @variants when variant.sku == sku
      return variant
    undefined

  _mget: (name) ->
    { metafields } = await Shopify.get @store,
        "/products/#{@_.id}/metafields.json"
    for field in metafields
      if "dashkite" == field.namespace && name == field.key
        return field
    # if not found...
    undefined

  mget: (name) ->
    metafield = await @_mget name
    if metafield?
      JSON.parse metafield.value

  mset: (name, value) ->
    # TODO do we need to detect that this is an update?
    Shopify.post @store, "/products/#{@_.id}/metafields.json", 
      metafield: meta name, value

  mdelete: (name) ->
    metafield = await @_mget name
    if metafield?
      await Shopify.del @store, "/metafields/#{metafield.id}.json",
    undefined

  clone: ->
    if @title.startsWith "/import"
      @_clone()

  parseCloneTitle: ->
    url = new URL @title.split(/\s+/)[1].trim()
    vendor = url.hostname.split(".")[0]
    [ ..., id ]= url.pathname.split "/"
    { vendor, id }

  _clone: ->
    { vendor, id } = @parseCloneTitle()
    await @mset "source", { vendor, id }
    supplier = await getStore vendor
    original = (await Product.get supplier, id)._
    @_ =
      id: @id
      title: original.title
      body_html: original.body_html
      vendor: original.vendor
      product_type: original.product_type
      handle: original.handle
      tags: original.tags
      images: do ->
        for image in original.images
          src: image.src
          position: image.position
          metafields: [
            meta "source", id: image.id
          ]
      options: do ->
        for option in original.options
          name: option.name
          position: option.position
          values: option.values
      variants: do =>
        for variant in original.variants
          variant.metafields ?= []
          variant.metafields.push meta "source",
            vendor: supplier.name
            id: variant.id
          # variant.inventory_management = "shopify"
          except [
            "id"
            "title"
            "product_id"
            "created_at"
            "updated_at"
            "admin_graphql_api_id"
            "image_id"
            # "inventory_quantity"
            "inventory_quantity_adjustment"
            "inventory_item_id"
            "inventory_management"
            "old_inventory_quantity"
            "fulfillment_service"
          ], variant

    await @put()

    for variant in original.variants
      supplierVariant = await ProductVariant.get supplier, variant.id
      await supplierVariant.mset "reseller",
        vendor: @store.name
        id: @getVariantFromSKU(supplierVariant.sku).id

    @

    # build up a mapping of image ids
    imageMap = {}
    for image in @images
      source = await image.mget "source"
      imageMap[ source.id ] = image.id

    # for each variant add the mapped image id
    await Promise.all await do =>
      for variant in @variants
        source = await variant.mget "source"
        originalVariant = original.variants.find (variant) -> variant.id == source.id
        if originalVariant.image_id?
          variant.image_id = imageMap[ originalVariant.image_id ]    
          # don't wait on response
          variant.put()

    @get()
        
export {
  Product
  ProductVariant
}
