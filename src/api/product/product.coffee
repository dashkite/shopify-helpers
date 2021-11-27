import * as Obj from "@dashkite/joy/object"
import * as Meta from "@dashkite/joy/metaclass"
import * as Iterable from "@dashkite/joy/iterable"
import * as Shopify from "../../shopify"
import { getStore } from "../../stores"
import { meta } from "../helpers"
import { ProductVariant } from "./variant"
import { ProductImage } from "./image"

parseCloneTitle = (title) ->
  url = new URL title.split(/\s+/)[1].trim()
  vendor = url.hostname.split(".")[0]
  [ ..., id ]= url.pathname.split "/"
  { vendor, id }

cloneCore = Obj.mask [
  "title",
  "body_html"
  "vendor"
  "product_type"
  "handle"
  "tags"
]

cloneOption = Obj.mask [ 
  "name", 
  "values", 
  "position" 
]

cloneVariant = Obj.exclude [
  "id"
  "title"
  "product_id"
  "created_at"
  "updated_at"
  "admin_graphql_api_id"
  "image_id"
  "inventory_quantity_adjustment"
  "inventory_item_id"
  "inventory_management"
  "old_inventory_quantity"
  "fulfillment_service"
]

cloneOptions = (options) -> 
  cloneOption option for option in options

cloneVariants = (supplier, variants) ->
  for variant in variants
    _variant = cloneVariant variant 
    _variant.metafields ?= []  
    _variant.metafields.push meta "source",
      vendor: supplier.name
      id: variant.id
    _variant
      

class Product

  @create: (store, {title, html, type, status, published, tags}) ->
    Object.assign new Product,
      store: store
      _: Obj.get "product",
        await Shopify.post store, "/products.json",
          product:
            title: title
            body_html: html
            product_type: type
            status: status ? "draft"
            published: published ? false
            tags: tags ? []

  @list: (store) ->
    { products } = await Shopify.get store, "/products.json?limit=250"
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
    @_ = Obj.get "product", 
      await Shopify.put @store, "/products/#{@_.id}.json", { product: @_ }
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

  createImage: (data) ->
    { image } = await Shopify.post @store, 
      "/products/#{@id}/images.json",
      image: data

    ProductImage.from @store, image

  cloneImage: (supplierImage) ->
    @createImage
      src: supplierImage.src
      position: supplierImage.position
      variant_ids: Iterable.project "id", @variants
      metafields: [
        meta "source", id: supplierImage.id
      ]


  clone: ->
    if @title.startsWith "/import"
      await @_clone()

  _clone: ->
    { vendor, id } = parseCloneTitle @title
    await @mset "source", { vendor, id }
    supplier = getStore vendor
    original = await Product.get supplier, id
   
    @_ = {
      id: @id
      ( cloneCore original._ )...
      options: cloneOptions original._.options
      variants: cloneVariants supplier, original._.variants 
    }

    # Preliminary put. Updates product and provides implicit variant creation.
    await @put()
      
    # Create cloned images with backward pointers to their source.
    imageMap = {}
    for supplierImage in original.images
      { id } = await @cloneImage supplierImage
      imageMap[ supplierImage.id ] = id

    # Target new variants with image and metadata association.
    for supplierVariant in original.variants
      resellerVariant = @getVariantFromSKU supplierVariant.sku

      # Set forward pointer from supplier variant to the reseller it created.
      await supplierVariant.mset "reseller",
        vendor: @store.name
        id: resellerVariant.id
      
      # Set image ID for each reseller variant with the new, equivalent image.
      if supplierVariant.image_id?
        resellerVariant.image_id = imageMap[ supplierVariant.image_id ]
        await resellerVariant.put()

    # Return the most up-to-date data of the clone.
    await @get()
        
export {
  Product
}
