package os

import "base:intrinsics"
import "base:runtime"
import "core:io"
import "core:strconv"
import "core:unicode/utf8"


OS :: ODIN_OS
ARCH :: ODIN_ARCH
ENDIAN :: ODIN_ENDIAN

SEEK_SET :: 0
SEEK_CUR :: 1
SEEK_END :: 2

write_string :: proc(fd: Handle, str: string) -> (int, Error) {
	return write(fd, transmute([]byte)str)
}

write_byte :: proc(fd: Handle, b: byte) -> (int, Error) {
	return write(fd, []byte{b})
}

write_rune :: proc(fd: Handle, r: rune) -> (int, Error) {
	if r < utf8.RUNE_SELF {
		return write_byte(fd, byte(r))
	}

	b, n := utf8.encode_rune(r)
	return write(fd, b[:n])
}

write_encoded_rune :: proc(f: Handle, r: rune) -> (n: int, err: Error) {
	wrap :: proc(m: int, merr: Error, n: ^int, err: ^Error) -> bool {
		n^ += m
		if merr != nil {
			err^ = merr
			return true
		}
		return false
	}

	if wrap(write_byte(f, '\''), &n, &err) { return }

	switch r {
	case '\a': if wrap(write_string(f, "\\a"), &n, &err) { return }
	case '\b': if wrap(write_string(f, "\\b"), &n, &err) { return }
	case '\e': if wrap(write_string(f, "\\e"), &n, &err) { return }
	case '\f': if wrap(write_string(f, "\\f"), &n, &err) { return }
	case '\n': if wrap(write_string(f, "\\n"), &n, &err) { return }
	case '\r': if wrap(write_string(f, "\\r"), &n, &err) { return }
	case '\t': if wrap(write_string(f, "\\t"), &n, &err) { return }
	case '\v': if wrap(write_string(f, "\\v"), &n, &err) { return }
	case:
		if r < 32 {
			if wrap(write_string(f, "\\x"), &n, &err) { return }
			b: [2]byte
			s := strconv.append_bits(b[:], u64(r), 16, true, 64, strconv.digits, nil)
			switch len(s) {
			case 0: if wrap(write_string(f, "00"), &n, &err) { return }
			case 1: if wrap(write_rune(f, '0'), &n, &err)    { return }
			case 2: if wrap(write_string(f, s), &n, &err)    { return }
			}
		} else {
			if wrap(write_rune(f, r), &n, &err) { return }
		}
	}
	_ = wrap(write_byte(f, '\''), &n, &err)
	return
}

read_at_least :: proc(fd: Handle, buf: []byte, min: int) -> (n: int, err: Error) {
	if len(buf) < min {
		return 0, io.Error.Short_Buffer
	}
	nn := max(int)
	for nn > 0 && n < min && err == nil {
		nn, err = read(fd, buf[n:])
		n += nn
	}
	if n >= min {
		err = nil
	}
	return
}

read_full :: proc(fd: Handle, buf: []byte) -> (n: int, err: Error) {
	return read_at_least(fd, buf, len(buf))
}


file_size_from_path :: proc(path: string) -> i64 {
	fd, err := open(path, O_RDONLY, 0)
	if err != nil {
		return -1
	}
	defer close(fd)

	length: i64
	if length, err = file_size(fd); err != nil {
		return -1
	}
	return length
}

read_entire_file_from_filename :: proc(name: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
	context.allocator = allocator

	fd, err := open(name, O_RDONLY, 0)
	if err != nil {
		return nil, false
	}
	defer close(fd)

	return read_entire_file_from_handle(fd, allocator, loc)
}

read_entire_file_from_handle :: proc(fd: Handle, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
	context.allocator = allocator

	length: i64
	err: Error
	if length, err = file_size(fd); err != nil {
		return nil, false
	}

	if length <= 0 {
		return nil, true
	}

	data, err = make([]byte, int(length), allocator, loc)
	if data == nil || err != nil {
		return nil, false
	}

	bytes_read, read_err := read_full(fd, data)
	if read_err != nil {
		delete(data)
		return nil, false
	}
	return data[:bytes_read], true
}

read_entire_file :: proc {
	read_entire_file_from_filename,
	read_entire_file_from_handle,
}

write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	flags: int = O_WRONLY|O_CREATE
	if truncate {
		flags |= O_TRUNC
	}

	mode: int = 0
	when OS == .Linux || OS == .Darwin {
		// NOTE(justasd): 644 (owner read, write; group read; others read)
		mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
	}

	fd, err := open(name, flags, mode)
	if err != nil {
		return false
	}
	defer close(fd)

	_, write_err := write(fd, data)
	return write_err == nil
}

write_ptr :: proc(fd: Handle, data: rawptr, len: int) -> (int, Error) {
	return write(fd, ([^]byte)(data)[:len])
}

read_ptr :: proc(fd: Handle, data: rawptr, len: int) -> (int, Error) {
	return read(fd, ([^]byte)(data)[:len])
}

heap_allocator_proc :: runtime.heap_allocator_proc
heap_allocator :: runtime.heap_allocator

heap_alloc  :: runtime.heap_alloc
heap_resize :: runtime.heap_resize
heap_free   :: runtime.heap_free

processor_core_count :: proc() -> int {
	return _processor_core_count()
}
