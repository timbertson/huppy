open Sys
module ExtUnix = ExtUnix.Specific

let log s = print_endline ("[ huppy ] " ^ s)

let shift ?(store:'a ref option) (arr:'a array) =
	Array.sub arr 1 ((Array.length arr) - 1)

let sleep sec = ignore (Unix.select [] [] [] sec)

let () =
	let args = ref (shift Sys.argv) in
	let cmd = ref !args.(0) in
	
	let shift () =
		args := shift !args;
		cmd := !args.(0)
	in

	let respond_to_input = match !cmd with
		| "-i" | "--input" ->
			shift ();
			true
		| _ -> false
	in

	let hupped = ref false in
	let killing = ref false in
	let child_group = ref None in

	let wait_child () =
		begin match !child_group with
			| Some grp -> (
				try
					while true do
						(* log ("waiting ..."); *)
						let (_, _) = Unix.waitpid [Unix.WUNTRACED] grp in
						()
					done
				with Unix.Unix_error (Unix.ECHILD, _, _) -> ();

				(* log ("child died, waiting for grandchildren ..."); *)
				try
					while true do
						try
							(* log ("sending kill 0 to group " ^ (string_of_int grp)); *)
							Unix.kill grp 0
						with Unix.Unix_error (Unix.EPERM, _, _) -> ();
						(* log ("sleep..."); *)
						sleep 0.1;
					done
				with Unix.Unix_error (Unix.ESRCH, _, _) -> ();
				(* log ("all processes dead"); *)
				print_endline "";
			)

			| None -> ()
		end;
		child_group := None;
	in

	let kill_child () =
		if not !killing then (
			killing := true;
			begin match !child_group with
				| Some grp -> (
					log ("killing " ^ (string_of_int grp));
					Unix.kill grp sigint;
					wait_child ();
				)
				| None -> ()
			end;
			killing := false
		)
	in

	let handle _ = hupped := true in
	let child_died _ =
		if not !killing then (
			log ("Child process ended (will run again on next HUP)");
			wait_child ()
		)
	in

	let cleanup = kill_child in

	let run first =
		cleanup ();
		hupped := false;
		match Unix.fork () with
			| 0 -> (
					ExtUnix.setpgid 0 0;
					Unix.execvp !cmd !args
				)
			| pid ->
					let action = if first then "Running" else "Restarted" in
					log (action ^ " " ^ !cmd ^ " (pid " ^ (string_of_int pid) ^ ")");
					child_group := Some (-pid)
	in

	set_signal sighup (Signal_handle handle);
	set_signal sigchld (Signal_handle child_died);
	set_signal sigint (Signal_handle (fun _ -> cleanup (); exit 1));

	run true;

	try
		while true do
			ignore (input_line stdin);
			if (respond_to_input) then (
				handle ();
			);
			while !hupped do
				run false
			done
		done
	with e -> (
		try cleanup () with _ -> ();
		raise e
	);
	cleanup ()
