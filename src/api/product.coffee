import * as Obj from "@dashkite/joy/object"
import * as Meta from "@dashkite/joy/metaclass"
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

  Meta.mixin @::, [
    Meta.getters
      inventory:->
        # make sure we have the latest
        await @get()
        @_.inventory_quantity
  ]

  setInventory: (value) ->
    { inventory_levels } = await Shopify.get @store,
      "/inventory_levels.json?inventory_item_ids=#{@_.inventory_item_id}"
    Shopify.post @store, "/inventory_levels/set.json",
      location_id: inventory_levels[0].location_id
      inventory_item_id: @_.inventory_item_id
      available: value

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

  mget: (name) ->
    { metafields } = await Shopify.get @store,
      "/products/#{@_.product_id}/variants/#{@_.id}/metafields.json"
    for field in metafields
      if "dashkite" == field.namespace && name == field.key
        return JSON.parse field.value
    # if not found...
    undefined

  mset: (name, value) ->
    Shopify.post @store, "/products/#{@_.product_id}/variants/#{@_.id}/metafields.json",
      metafield: meta name, value

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

  mget: (name) ->
    { metafields } = await Shopify.get @store, "/products/#{@_.id}/metafields.json"
    for field in metafields
      if "dashkite" == field.namespace && name == field.key
        return JSON.parse field.value
    # if not found...
    undefined

  mset: (name, value) ->
    # TODO do we need to detect that this is an update?
    Shopify.post @store, "/products/#{@_.id}/metafields.json", 
      metafield: meta name, value

  sync: ->
    @source ?= await @mget "source"
    if @source.initialized != true
      await @clone()
      @source.initialized = true
      await @mset "source", @source
    @syncInventory()

  syncInventory: ->

  clone: ->
    @source ?= await @mget "source"
    @supplier ?= await getStore @source.vendor
    @original ?= await Product.get @supplier, @source.id
    original = @original._
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
            vendor: @supplier.name
            id: variant.id
          variant.inventory_management ="shopify"
          except [
            "id"
            "title"
            "product_id"
            "created_at"
            "updated_at"
            "admin_graphql_api_id"
            "image_id"
            "inventory_quantity"
            "inventory_quantity_adjustment"
            "inventory_item_id"
            "inventory_management"
            "old_inventory_quantity"
            "fulfillment_service"
          ], variant

    await @put()

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
