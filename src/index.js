import readline from "readline"
import fs from "fs/promises"
import { Readable } from "stream"
import chokidar from "chokidar"

const csgoLogFile = 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Counter-Strike Global Offensive\\csgo\\console.log'
const matchReadyRegex = /ready/
const matchClosed = /peer closed/

;(async () => {

let getCahnges

await fs.rm(csgoLogFile, { force: true })
	.then(
		() => fs.writeFile(csgoLogFile, ""),
		() => console.log("Cannot remove csgo log file. Looks like csgo is alredy blocked it")
	).catch(error => {
		console.log("Cannot create empty csgo log file")
		throw error
	})
await fs.readFile(csgoLogFile)
	.then(logs => getCahnges = createCahngesParser(logs))
	.catch(error => {
		console.log("Cannot read csgo log file")
		throw error
	})


chokidar.watch(csgoLogFile, { usePolling: true }).on('change', async path => {
	const changes = await getCahnges(path)
	
	for await (const command of readByLine(changes)) {
		if (matchReadyRegex.test(command))
			console.log("Match is ready!")
		if (matchClosed.test(command))
			console.log("Ooops, it looks like you missed your match")
	}
})

})()

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
