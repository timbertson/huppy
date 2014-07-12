open Sys
module ExtUnix = ExtUnix.Specific

let log s = print_endline ("[ huppy ] " ^ s)

let shift ?(store:'a ref option) (arr:'a array) =
	Array.sub arr 1 ((Array.length arr) - 1)

let sleep sec = ignore (Unix.select [] [] [] sec)

exception Failure of string

let wait_child (child_group:int option ref) =
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
		)

		| None -> ()
	end;
	child_group := None

let cleanup ~killing ~child_group () =
	if not !killing then (
		killing := true;
		begin match !child_group with
			| Some grp -> (
				log ("Killing group " ^ (string_of_int grp));
				Unix.kill grp sigint;
				wait_child child_group;
			)
			| None -> ()
		end;
		killing := false;
		(* print_endline "kill done" *)
	)

let trigger_restart ~should_restart () =
	should_restart := true

let ignore_eintr f a =
	try f a with Unix.Unix_error (Unix.EINTR, _, _) -> ()

let stdin_loop ~trigger_restart action =
	Unix.set_nonblock Unix.stdin;

	let rec read_until_newline () =
		let ch =
			try Some (input_char stdin)
			with
				| Unix.Unix_error (Unix.EWOULDBLOCK, _, _)
				| Unix.Unix_error (Unix.EAGAIN, _, _)
				-> None
		in
		match ch with
			| None -> false
			| Some '\n' -> true
			| Some _ -> read_until_newline ()
	in

	while true do
		ignore_eintr (fun () ->
			let fd = Unix.stdin in
			let readable, _, errored = Unix.select [fd] [] [fd] 1000.0 in
			if errored <> [] then raise (Failure "error on stdin");
			(* print_endline ("select done. there are " ^ *)
			(* 	(string_of_int (List.length readable)) ^ " readables"); *)
			if List.mem fd readable then
				if read_until_newline () then
					trigger_restart ()
		) ();
		action ()
	done

let run_child_loop ~should_restart ~run_child () =
	while !should_restart do
		run_child false
	done

let sleep_loop action =
	while true do
		ignore_eintr Unix.sleep 1000;
		action ()
	done

let child_died ~killing ~child_group () =
	if not !killing then (
		log ("Child process ended (will run again on next HUP)");
		wait_child child_group
	)

let run_child ~killing ~child_group ~should_restart ~cmd ~args first =
	cleanup ~killing ~child_group ();
	should_restart := false;
	match Unix.fork () with
		| 0 -> (
				ExtUnix.setpgid 0 0;
				Unix.execvp cmd args
			)
		| pid ->
				let action = if first then "Running" else "Restarted" in
				log (action ^ " " ^ cmd ^ " (pid " ^ (string_of_int pid) ^ ")");
				child_group := Some (-pid)

let print_help () =
	prerr_endline (
		""
		^ "  Usage: huppy [OPTIONS] <command> [ARGS]\n"
		^ "\n"
		^ "  OPTIONS:\n"
		^ "    -i, --input      Also restart on newline (return)\n"
		^ "\n"
		^ "  ABOUT:\n"
		^ "    huppy will start a long-running command, and\n"
		^ "    kill / restart it whenever you send a HUP signal"

	)

let () =
	let args = ref (shift Sys.argv) in
	let cmd =
		try ref !args.(0)
		with Invalid_argument _ -> print_help (); exit 1
	in
	
	let shift () =
		args := shift !args;
		cmd := !args.(0)
	in

	begin match !cmd with
		| "-h" | "--help" ->
			print_help ();
			exit 0
		| _ -> ()
	end;

	let respond_to_input = match !cmd with
		| "-i" | "--input" ->
			shift ();
			true
		| _ -> false
	in

	let should_restart = ref false in
	let killing = ref false in
	let child_group = ref None in

	(* inject dependencies *)
	let trigger_restart = trigger_restart ~should_restart in
	let cleanup = cleanup ~killing ~child_group in
	let child_died = child_died ~killing ~child_group in
	let run_child = run_child ~killing ~child_group ~should_restart ~cmd:!cmd ~args:!args in
	let run_loop = run_child_loop ~should_restart ~run_child in
	let stdin_loop = stdin_loop ~trigger_restart in

	set_signal sighup (Signal_handle (fun _ -> trigger_restart ()));
	set_signal sigchld (Signal_handle (fun _ -> child_died ()));
	set_signal sigint (Signal_handle (fun _ -> cleanup (); exit 1));

	if respond_to_input then Unix.set_close_on_exec Unix.stdin;

	try
		run_child true;
		if respond_to_input
			then stdin_loop run_loop
			else sleep_loop run_loop
		;
	with e -> (
		(* log ("ERRROR: " ^(Printexc.to_string e)); *)
		(try cleanup () with _ -> ());
		let () = raise e in ()
	);
	cleanup ()
