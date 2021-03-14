import { createStore } from "redux"
import reducer from "./reducer.js"
import { createObserver } from "./observer.js"

export const store = createStore(reducer)
export const observe = createObserver(store)
