open Sys

let log s = print_endline ("[ huppy ] " ^ s)


let () =
	let args = Array.sub Sys.argv 1 ((Array.length Sys.argv) - 1) in
	(* print_endline ((String.concat ", " (Array.to_list args))); *)
	let cmd = args.(0) in

	let hupped = ref false in
	let killing = ref false in
	let child_pid = ref None in

	let handle _ = hupped := true in
	let child_died _ =
		if not !killing then log ("Child process ended (will run again on next HUP)");
		child_pid := None
	in

	let cleanup () =
		match !child_pid with
			| Some pid ->
					killing := true;
					Unix.kill pid sigint;
					let (_, _) = Unix.waitpid [] pid in
					killing := false
			| None -> ()
	in

	let run first =
		cleanup ();
		hupped := false;
		match Unix.fork () with
			| 0 -> Unix.execvp cmd args
			| pid ->
					let action = if first then "Running" else "Restarted" in
					log (action ^ " " ^ cmd ^ " (pid " ^ (string_of_int pid) ^ ")");
					child_pid := Some pid
	in

	set_signal sighup (Signal_handle handle);
	set_signal sigchld (Signal_handle child_died);

	run true;
	try
		while true do
			Unix.sleep 10000;
			while !hupped do
				run false
			done
		done
	with e -> (
		log "cleanup";
		try cleanup () with _ -> ();
		raise e
	);
	cleanup ()
