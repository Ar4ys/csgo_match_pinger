import readline from "readline"
import fs from "fs/promises"
import { Readable } from "stream"
import chokidar from "chokidar"
import { store, observe } from "./store/index.js"
import { startWatching, stopWatching, csgoStarted, csgoStopped } from "./store/actions.js"

const csgoLogFile = 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Counter-Strike Global Offensive\\csgo\\console.log'
const matchReadyRegex = /ready/
const matchClosed = /peer closed/

fs.rm(csgoLogFile, { force: true })
	.then(() => waitForCSGO())
	.catch(() => {
		console.log(
			"Cannot remove csgo log file. " +
			"Looks like csgo is alredy blocked it"
		)
		store.dispatch(csgoStarted())
	})

observe(
	({ isCSGORunning }) => [ isCSGORunning, isCSGORunning ],
	async () => {
		const logParser = await initLogParser(csgoLogFile)
		const watcher = chokidar
			.watch(csgoLogFile, { usePolling: true })
			.on('change', createLogHandler(logParser))
		store.dispatch(startWatching(watcher))
		startPingingCSGO()
	}
)

observe(
	({ isCSGORunning, watcher }) => {
		return [ watcher, !isCSGORunning && (watcher ?? false) ]
	},
	async watcher => {
		console.log("CSGO Stopped")
		await watcher.close()
		store.dispatch(stopWatching())
	}
)

observe(
	({ isCSGORunning, watcher }) => {
		return [ watcher, !watcher && !isCSGORunning ]
	},
	() => {
		waitForCSGO()
	}
)

function createLogHandler(logParser) {
	return async logFile => {
		const changes = await logParser(logFile)
				
		for await (const command of readByLine(changes)) {
			if (matchReadyRegex.test(command))
				console.log("Match is ready!")
			if (matchClosed.test(command))
				console.log("Ooops, it looks like you missed your match")
		}
	}
}

function startPingingCSGO() {
	const id = setInterval(() => {
		fs.rm(csgoLogFile, { force: true })
			.then(() => {
				clearInterval(id)
				store.dispatch(csgoStopped())
			})
			.catch(() => {})
	}, 1000)
}

function waitForCSGO() {
	const watcher = chokidar.watch(csgoLogFile, { depth: 0 }).once("add", async () => {
		console.log("gotcha")
		await watcher.close()
		store.dispatch(csgoStarted())
	})

	return watcher
}

async function initLogParser(logFile) {
	return await fs.readFile(logFile)
		.then(logs => createCahngesParser(logs))
		.catch(error => {
			console.log("Cannot read csgo log file")
			throw error
		})
}

function createCahngesParser(prevState = "") {
	return async path => {
		const newString = await fs.readFile(path, "utf8")
		const changes = newString.replace(prevState, "")
		prevState = newString
		return changes
	}
}

function readByLine(string) {
	return readline.createInterface({
	    input: Readable.from(string)
	})
}
