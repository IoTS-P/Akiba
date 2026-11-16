// A plan that exercises the module plumbing end to end.
//
// Run it from the machine that holds the projects:
//   akiba -p examples/plan-demo.kts
//
// It asks the index for the programs in project `test`, runs PlanDemo over each one with
// a label of its own, and prints what came back. Nothing is written to a database: these
// programs have no binary row, so the data comes back to this script instead.

val progs = programs("project_dir LIKE '%/test'").expect()
println("programs: ${progs.size}")

val runs = runAll(progs) { p ->
    ModuleSpec("org.iotsplab.akiba.process.PlanDemo")
        .withConfig(mapOf("label" to p.name, "maxFunctions" to 100))
}.expect()

runs.forEach { (programId, run) ->
    // statusName is SUCCESS for 0, a framework name for 1..99, EXIT_<n> for module codes.
    println("$programId ${run.statusName} ${run.result}")
}
