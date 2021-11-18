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
      wait: 15000
      value

import stores from "./stores"

do ({ reseller, supplier, products, product, order, webhook } = {}) ->

  $.addStores stores

  reseller = $.getStore "Test-Reseller"
  supplier = $.getStore "Test-Supplier"

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
      product.mset "source",
        vendor: "Test-Supplier"
        id: "7448670601434"

    await test "Get metafield", target "product", ->
      value = await product.mget "source"
      assert.equal "Test-Supplier", value.vendor
      assert.equal "7448670601434", value.id

    await test "Get metafield that is undefined", target "product", ->
      value = await product.mget "foobar"
      assert !value?

    await test "List products", target "product", ->
      products = await $.Product.list reseller
      assert products.length?
      assert products.length > 0

    await test "Sync product", await target "sync", ->
      await product.sync()

    await test "Get inventory levels", await target "sync", ->
      assert.equal 0, await product.variants[0].inventory

    await test "Set inventory level", await target "sync", ->
      await product.variants[0].setInventory 5
      assert.equal 5, await product.variants[0].inventory

    await test "Create Order", await target "sync", ->
      order = await $.Order.create reseller,
        items: [
          variant: product.variants[0]
          quantity: 1
        ]
      assert order._?
      assert order._.id?
      assert order._.line_items?

    await test "Forward Order", await target "sync", ->
      console.log await order.forward()

    await test "Delete product", target "product", ->

      for product in products
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

