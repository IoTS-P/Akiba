// Does a module that changes the program get to do so?
//
// ZeroTrimmer edits memory blocks, so it needs a writable program. The plan runtime opens
// programs read-only today; this script says what that looks like from the script's side.

val progs = programs("project_dir LIKE '%/test'").expect()
val runs = runAll(progs, ModuleSpec("org.iotsplab.akiba.process.ZeroTrimmer")).expect()
runs.forEach { (id, run) -> println("$id ${run.statusName} ${run.result}") }
