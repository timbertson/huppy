open Sys
module ExtUnix = ExtUnix.Specific

let log s = print_endline ("[ huppy ] " ^ s)

let shift ?(store:'a ref option) (arr:'a array) =
	Array.sub arr 1 ((Array.length arr) - 1)

let sleep sec = ignore (Unix.select [] [] [] sec)

exception Failure of string

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
					log ("Killing group " ^ (string_of_int grp));
					Unix.kill grp sigint;
					wait_child ();
				)
				| None -> ()
			end;
			killing := false;
			(* print_endline "kill done" *)
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

	if respond_to_input then Unix.set_close_on_exec Unix.stdin;

	run true;

	let ignore_eintr f a =
		try f a with Unix.Unix_error (Unix.EINTR, _, _) -> ()
	in

	let stdin_loop action =
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
						handle ()
			) ();
			action ()
		done
	in

	let sleep_loop action =
		while true do
			ignore_eintr Unix.sleep 1000;
			action ()
		done
	in

	let do_run () =
		while !hupped do
			run false
		done
	in

	try
		stdin_loop do_run;
		if respond_to_input
			then stdin_loop do_run
			else sleep_loop do_run
		;
	with e -> (
		(* log ("ERRROR: " ^(Printexc.to_string e)); *)
		(try cleanup () with _ -> ());
		let () = raise e in ()
	);
	cleanup ()
