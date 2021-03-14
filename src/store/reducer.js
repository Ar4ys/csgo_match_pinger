import { csgoStarted, csgoStopped, startWatching, stopWatching } from "./actions.js"

const initState = {
	csgoStarted: false,
	isWatching: false
}

export default function reducer(state = initState, { type, payload }) {
	switch (type) {
		case csgoStarted.type:
			return { ...state, isCSGORunning: true }

		case csgoStopped.type:
			return { ...state, isCSGORunning: false }

		case startWatching.type:
			return { ...state, watcher: payload }

		case stopWatching.type:
			return { ...state, watcher: undefined }

		default:
			return state
	}
}
