export function createObserver(store) {
	return (selector, callback) => {
		let currentState
		let unsubscribe = store.subscribe(() => {
			const [ nextState, shouldUpdate ] = selector(store.getState())
			if (shouldUpdate)
				callback(nextState)
			currentState = nextState
		})
		
		return unsubscribe
	}
}
