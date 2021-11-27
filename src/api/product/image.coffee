import * as Meta from "@dashkite/joy/metaclass"
import * as Shopify from "../../shopify"
import { meta } from "../helpers"

class ProductImage

  @from: (store, data) ->
    Object.assign new ProductImage,
      store: store
      _: data

  Meta.mixin @::, [
    Meta.getters
      id: -> @_.id
      src: -> @_.src
      position: -> @_.position
  ]

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


export {
  ProductImage
}
