export const csgoStarted = createAction("csgoStarted")
export const csgoStopped = createAction("csgoStopped")
export const startWatching = createAction("startWatching")
export const stopWatching = createAction("stopWatching")

function createAction(type) {
	const action = payload => ({ type, payload })
	action.type = type
	return action
}