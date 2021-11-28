import { test as _test, success } from "@dashkite/amen"
import print from "@dashkite/amen-console"
import assert from "@dashkite/assert"

import * as $ from "../src"

targets = (process.env.targets?.split /\s+/) ? []

target = (name, value) -> value if name in targets

test = (name, value) ->
  if Array.isArray value
    _test name, value
  else
    _test
      description: name
      wait: 20000
      value

import stores from "./stores"

do ({ source, reseller, supplier, products, product, order, webhook } = {}) ->

  

  $.addStores stores

  supplier = $.getStore "playtyme-test-supplier"
  reseller = $.getStore "playtyme-test-reseller"
  seedProduct = await $.Product.get supplier, "7465463709914"
  seedProduct.url = "https://playtyme-test-supplier.myshopify.com/admin/products/7465463709914"

  print await test "Shopify Helpers", [

    await test "Create Product", target "product", ->
      product = await $.Product.create reseller,
        title: "Test Product"
        html: "This is a test product."
        vendor: "Acme, Inc."
        type: "Test"
        tags: [ "Test" ]

      assert product._.id?

    await test "Add metafield", target "product", ->
      await product.mset "source",
        vendor: "playtyme-test-supplier"
        id: seedProduct.id

      await product.mset "source2",
        vendor: "playtyme-test-supplier"
        id: seedProduct.id

    await test "Get metafield", target "product", ->
      value = await product.mget "source"
      assert.equal "playtyme-test-supplier", value.vendor
      assert.equal seedProduct.id, value.id

    await test "Delete metafield / Get undefined", target "product", ->
      assert ( await product.mget "source2" )?
      await product.mdelete "source2"
      assert !( await product.mget "source2" )?

    await test "List products", target "product", ->
      products = await $.Product.list reseller
      assert products.length?
      assert products.length > 0

    await test "Clone product", await target "clone", ->
      supplier.product = await $.Product.create supplier,
        title: "/import #{seedProduct.url}"
        tags: [ "Test" ]
      await supplier.product.clone()
      await supplier.product.mdelete "source"
      await variant.mdelete "source" for variant in supplier.product.variants

      product = await $.Product.create reseller,
        title: "/import https://playtyme-test-supplier.myshopify.com/admin/products/#{supplier.product.id}"
        tags: [ "Test" ]
      await product.clone()

    # TODO: Test forward pointer.
    # await test "Get Variant From SKU", target "clone", ->
    #   sku = product.variants[0].sku
    #   _variant = await $.ProductVariant.getFromSKU reseller, sku
    #   assert.equal product.variants[0].id, _variant.id

    await test "Get inventory levels", await target "inventory", ->
      assert.equal 5, await product.variants[0].getInventory()

    await test "Set inventory level", await target "inventory", ->
      # ensure we're tracking inventory, in case we didn't run clone test
      product.variants[0]._.inventory_management = "shopify"
      await product.variants[0].put()
      await product.variants[0].setInventory 10
      assert.equal 10, await product.variants[0].getInventory()

    await test "Create Order", await target "order", ->
      order = await $.Order.create reseller,
        shippingAddress:
          address1: "123 Main St"
          city: "Los Angeles"
          country: "United States"
          first_name: "John"
          last_name: "Doe"
          name: "John Doe"
          province: "California"
          zip: "90012"
        items: [
          variant: product.variants[0]
          quantity: 1
        ]
      assert order._?
      assert order._.id?
      assert order._.line_items?

    await test "Forward Order", await target "order", ->
      orders = await order.forward()
      assert.equal 1, orders.length

    await test "Inventory Update", await target "inventory", ->
      variant = await $.ProductVariant.getFromInventoryItem reseller, 
        product.variants[0]._.inventory_item_id
      assert.equal variant.id, product.variants[0].id

    await test "Delete product", target "product", ->

      await supplier.product.delete() if supplier.product?

      for product in ( await $.Product.list reseller )
        await product.delete() 

      products = await $.Product.list reseller
      assert products.length?
      assert.equal 0, products.length

    await test "Create Webhook", await target "webhook", ->
      webhook = await $.Webhook.create reseller,
        topic: "products/create"
        address: "https://playtyme.dashkite.io/products/create"
        fields: [ "id" ]
      assert webhook._.id?

    await test "List Webhooks", await target "webhook", ->
      webhooks = await $.Webhook.list reseller
      assert webhooks.length > 0

    await test "Delete Webhook", await target "webhook", ->
      await webhook.delete()
      assert webhook.deleted

  ]
  
  process.exit success

