stores = {}

addStore = (name, description) -> stores[ name ] = { description..., name }

addStores = (stores) -> addStore name, description for name, description of stores
    
getStore = (name) -> stores[ name ]

getStores = -> stores

export {
  addStore
  addStores
  getStores
  getStore
}