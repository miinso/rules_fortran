! module_order: works out in which order the sources of one target must be
! seen so that every MODULE is compiled before the sources that USE it.
!
! usage: module_order <params file>
!   the params file holds one `key value` per line:
!     order <path>     the order file to write
!     empty <path>     the placeholder source to write
!     src <path>       a source of the target (any order)
!     file <path>      a declared file that INCLUDE / #include may read (hdrs)
!     include <dir>    a dir INCLUDE / #include searches, in this order
!     option openmp                 `!$` lines are code (-fopenmp)
!     option d-lines-as-code        fixed-form `d` lines are code
!     option fixed-line-length <n>  fixed-form line width, 0 = none (default 72)
!     option cpp                    every source is preprocessed, not only .F/.F90/...
!     dump <path>      testing only: writes what was read from each source
!
! the order file is a compiler response file listing every source that defines
! a module or submodule, each after the sources whose modules it uses. sources
! that define no module are left out: nothing needs them compiled first. when
! no source defines one it lists the placeholder, so it is never empty.
!
! this is a statement scanner, not a parser. it joins continuation lines, skips
! comments and strings, follows INCLUDE / #include files among the declared
! files, and reads `module x`, `submodule (p) x` and `use x` at the start of a
! statement. it does not run the preprocessor: every #if branch is read, so an
! inactive `use` can add an ordering edge (and with it a false cycle), and an
! inactive `module` can add a false duplicate.
program module_order
  use, intrinsic :: iso_fortran_env, only: error_unit, iostat_end, iostat_eor
  implicit none

  type :: string
    character(len=:), allocatable :: s
  end type string

  ! text that grows by appending, without a copy of all of it each time
  type :: buffer
    character(len=:), allocatable :: s
    integer :: n = 0
  end type buffer

  integer, parameter :: max_include_depth = 16

  logical :: openmp = .false., d_lines_as_code = .false., cpp_everywhere = .false.
  integer :: fixed_line_length = 72
  character(len=:), allocatable :: order_path, empty_path, dump_path

  type(string), allocatable :: srcs(:), files(:), include_dirs(:)
  integer :: n_srcs = 0, n_files = 0, n_include_dirs = 0
  integer, allocatable :: files_sorted(:)

  ! what each source provides and needs. the entries of one source are
  ! contiguous; origin is the file a module statement was read from
  type(string), allocatable :: provide_name(:), provide_origin(:), need_name(:)
  integer, allocatable :: provide_owner(:), need_owner(:)
  integer :: n_provides = 0, n_needs = 0
  integer, allocatable :: first_provide(:), last_provide(:), first_need(:), last_need(:)
  integer, allocatable :: provides_sorted(:)

  integer, allocatable :: state(:), sorted(:)
  integer :: n_sorted = 0
  integer :: i

  allocate(srcs(16), files(16), include_dirs(16), provide_name(16), provide_origin(16), need_name(16))
  allocate(provide_owner(16), need_owner(16))
  call read_params()

  allocate(first_provide(n_srcs), last_provide(n_srcs), first_need(n_srcs), last_need(n_srcs))
  do i = 1, n_srcs
    first_provide(i) = n_provides + 1
    first_need(i) = n_needs + 1
    call scan_file(i, srcs(i)%s, is_fixed_form(srcs(i)%s), &
                   cpp_everywhere .or. is_preprocessed(srcs(i)%s), 0)
    last_provide(i) = n_provides
    last_need(i) = n_needs
  end do
  if (allocated(dump_path)) call dump()

  provides_sorted = sort_index(provide_name, n_provides)
  call check_duplicates()
  call order_sources()
  call write_outputs()

contains

  subroutine die(message)
    character(len=*), intent(in) :: message
    write(error_unit, "(A)") "module_order: " // message
    error stop 1
  end subroutine die

  ! ---- params ----

  subroutine read_params()
    character(len=:), allocatable :: params, line, key, value
    integer :: unit, status, length, blank, k
    logical :: first
    call get_command_argument(1, length=length)
    if (length == 0) call die("usage: module_order <params file>")
    allocate(character(len=length) :: params)
    call get_command_argument(1, params)
    open(newunit=unit, file=params, status="old", action="read", iostat=status)
    if (status /= 0) call die("cannot open " // params)
    first = .true.
    do
      call read_record(unit, line, status)
      if (status /= 0) exit
      if (first) call strip_bom(line)
      first = .false.
      call drop_cr(line)
      line = trim(line)
      if (len(line) == 0) cycle
      blank = index(line, " ")
      if (blank == 0) then
        key = line
        value = ""
      else
        key = line(1:blank - 1)
        value = line(blank + 1:)
      end if
      select case (key)
      case ("order")
        order_path = value
      case ("empty")
        empty_path = value
      case ("dump")
        dump_path = value
      case ("src")
        call add(srcs, n_srcs, normalized(value))
      case ("file")
        call add(files, n_files, normalized(value))
      case ("include")
        call add(include_dirs, n_include_dirs, normalized(value))
      case ("option")
        call set_option(value)
      case default
        call die("unknown params line: " // line)
      end select
    end do
    close(unit)
    if (.not. allocated(order_path) .or. .not. allocated(empty_path)) &
      call die("params file needs an `order` and an `empty` line")
    ! sources can be included too
    do k = 1, n_srcs
      call add(files, n_files, srcs(k)%s)
    end do
    files_sorted = sort_index(files, n_files)
  end subroutine read_params

  subroutine set_option(value)
    character(len=*), intent(in) :: value
    integer :: status
    if (value == "openmp") then
      openmp = .true.
    else if (value == "d-lines-as-code") then
      d_lines_as_code = .true.
    else if (value == "cpp") then
      cpp_everywhere = .true.
    else if (starts_with(value, "fixed-line-length ")) then
      read(value(19:), *, iostat=status) fixed_line_length
      if (status /= 0) call die("bad option: " // value)
    else
      call die("unknown option: " // value)
    end if
  end subroutine set_option

  ! ---- growable lists ----

  subroutine add(list, n, value)
    type(string), allocatable, intent(inout) :: list(:)
    integer, intent(inout) :: n
    character(len=*), intent(in) :: value
    call reserve(list, n + 1)
    n = n + 1
    list(n)%s = value
  end subroutine add

  ! element by element: whole-array copies of deferred-length components
  ! crash some compilers (gfortran 11)
  subroutine reserve(list, needed)
    type(string), allocatable, intent(inout) :: list(:)
    integer, intent(in) :: needed
    type(string), allocatable :: grown(:)
    integer :: k
    if (needed <= size(list)) return
    allocate(grown(max(2 * size(list), needed)))
    do k = 1, size(list)
      if (allocated(list(k)%s)) call move_alloc(list(k)%s, grown(k)%s)
    end do
    call move_alloc(grown, list)
  end subroutine reserve

  subroutine reserve_int(list, needed)
    integer, allocatable, intent(inout) :: list(:)
    integer, intent(in) :: needed
    integer, allocatable :: grown(:)
    if (needed <= size(list)) return
    allocate(grown(max(2 * size(list), needed)))
    grown(1:size(list)) = list
    call move_alloc(grown, list)
  end subroutine reserve_int

  subroutine add_provide(owner, name, origin)
    integer, intent(in) :: owner
    character(len=*), intent(in) :: name, origin
    call reserve(provide_name, n_provides + 1)
    call reserve(provide_origin, n_provides + 1)
    call reserve_int(provide_owner, n_provides + 1)
    n_provides = n_provides + 1
    provide_name(n_provides)%s = name
    provide_origin(n_provides)%s = origin
    provide_owner(n_provides) = owner
  end subroutine add_provide

  subroutine add_need(owner, name)
    integer, intent(in) :: owner
    character(len=*), intent(in) :: name
    call reserve(need_name, n_needs + 1)
    call reserve_int(need_owner, n_needs + 1)
    n_needs = n_needs + 1
    need_name(n_needs)%s = name
    need_owner(n_needs) = owner
  end subroutine add_need

  ! ---- text helpers ----

  ! one record of any length. a last line without a newline still counts
  subroutine read_record(unit, line, status)
    integer, intent(in) :: unit
    character(len=:), allocatable, intent(out) :: line
    integer, intent(out) :: status
    character(len=1024) :: chunk
    type(buffer) :: record
    integer :: got
    do
      got = 0
      read(unit, "(A)", advance="no", size=got, iostat=status) chunk
      call append(record, chunk(1:got))
      if (status == 0) cycle
      if (status == iostat_eor) status = 0
      if (status == iostat_end .and. record%n > 0) status = 0
      line = record%s(1:record%n)
      return
    end do
  end subroutine read_record

  subroutine append(b, text)
    type(buffer), intent(inout) :: b
    character(len=*), intent(in) :: text
    character(len=:), allocatable :: grown
    if (.not. allocated(b%s)) allocate(character(len=max(256, len(text))) :: b%s)
    if (b%n + len(text) > len(b%s)) then
      allocate(character(len=max(2 * len(b%s), b%n + len(text))) :: grown)
      grown(1:b%n) = b%s(1:b%n)
      call move_alloc(grown, b%s)
    end if
    b%s(b%n + 1:b%n + len(text)) = text
    b%n = b%n + len(text)
  end subroutine append

  subroutine strip_bom(line)
    character(len=:), allocatable, intent(inout) :: line
    if (starts_with(line, char(239) // char(187) // char(191))) line = line(4:)
  end subroutine strip_bom

  subroutine drop_cr(line)
    character(len=:), allocatable, intent(inout) :: line
    if (len(line) > 0) then
      if (line(len(line):len(line)) == achar(13)) line = line(1:len(line) - 1)
    end if
  end subroutine drop_cr

  ! tabs, stray carriage returns, form feeds and non-breaking spaces are blanks
  subroutine blank_out(line)
    character(len=*), intent(inout) :: line
    integer :: k
    do k = 1, len(line)
      select case (iachar(line(k:k)))
      case (9, 12, 13)
        line(k:k) = " "
      case (160)
        line(k:k) = " "
        if (k > 1) then
          if (line(k - 1:k - 1) == char(194)) line(k - 1:k - 1) = " "
        end if
      end select
    end do
  end subroutine blank_out

  subroutine lower(text)
    character(len=*), intent(inout) :: text
    integer :: k, code
    do k = 1, len(text)
      code = iachar(text(k:k))
      if (code >= iachar("A") .and. code <= iachar("Z")) text(k:k) = achar(code + 32)
    end do
  end subroutine lower

  function lowered(text) result(out)
    character(len=*), intent(in) :: text
    character(len=:), allocatable :: out
    out = text
    call lower(out)
  end function lowered

  logical function starts_with(text, prefix)
    character(len=*), intent(in) :: text, prefix
    starts_with = .false.
    if (len(text) >= len(prefix)) starts_with = text(1:len(prefix)) == prefix
  end function starts_with

  ! text from position k on, without the blanks around it
  function after(text, k) result(out)
    character(len=*), intent(in) :: text
    integer, intent(in) :: k
    character(len=:), allocatable :: out
    if (k > len(text)) then
      out = ""
    else
      out = trim(adjustl(text(k:)))
    end if
  end function after

  ! length of the name text starts with (0 if none). `$` is a flang extension
  integer function name_length(text)
    character(len=*), intent(in) :: text
    name_length = verify(text, "abcdefghijklmnopqrstuvwxyz0123456789_$") - 1
    if (name_length < 0) name_length = len(text)
  end function name_length

  logical function ends_in_backslash(line)
    character(len=*), intent(in) :: line
    integer :: k
    k = len_trim(line)
    ends_in_backslash = .false.
    if (k > 0) ends_in_backslash = line(k:k) == achar(92)
  end function ends_in_backslash

  ! a preprocessor line. in fixed form a `#` in column 6 continues a statement
  logical function is_directive(line, fixed)
    character(len=*), intent(in) :: line
    logical, intent(in) :: fixed
    integer :: p
    is_directive = .false.
    p = verify(line, " " // achar(9))
    if (p == 0) return
    if (line(p:p) /= "#") return
    if (fixed .and. p == 6) return
    is_directive = .true.
  end function is_directive

  function extension(path) result(ext)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: ext
    integer :: dot
    dot = index(path, ".", back=.true.)
    if (dot == 0 .or. dot < index(path, "/", back=.true.)) then
      ext = ""
    else
      ext = path(dot + 1:)
    end if
  end function extension

  logical function is_fixed_form(path)
    character(len=*), intent(in) :: path
    is_fixed_form = extension(path) == "f" .or. extension(path) == "F"
  end function is_fixed_form

  logical function is_preprocessed(path)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: ext
    ext = extension(path)
    is_preprocessed = ext == "F" .or. ext == "F90" .or. ext == "F95" .or. ext == "F03" .or. ext == "F08"
  end function is_preprocessed

  ! ---- paths ----

  function join(dir, name) result(out)
    character(len=*), intent(in) :: dir, name
    character(len=:), allocatable :: out
    if (len(dir) == 0) then
      out = name
    else
      out = dir // "/" // name
    end if
  end function join

  function dirname(path) result(out)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: out
    integer :: slash
    slash = index(path, "/", back=.true.)
    if (slash == 0) then
      out = ""
    else
      out = path(1:slash - 1)
    end if
  end function dirname

  ! forward slashes, no `.` parts, `a/..` folded
  function normalized(path) result(out)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: out, p, part
    integer :: start, slash, k
    logical :: absolute
    p = path
    do k = 1, len(p)
      if (p(k:k) == achar(92)) p(k:k) = "/"
    end do
    absolute = starts_with(p, "/")
    out = ""
    start = 1
    do while (start <= len(p))
      slash = index(p(start:), "/")
      if (slash == 0) then
        part = p(start:)
        start = len(p) + 1
      else
        part = p(start:start + slash - 2)
        start = start + slash
      end if
      if (len(part) == 0) cycle
      if (part == ".") cycle
      if (part == "..") then
        k = index(out, "/", back=.true.)
        if (len(out) > 0 .and. out(k + 1:) /= "..") then
          out = out(1:max(k - 1, 0))
          cycle
        end if
      end if
      out = join(out, part)
    end do
    if (absolute) out = "/" // out
  end function normalized

  ! stable merge sort; the indices of list(1:n) in name order
  function sort_index(list, n) result(idx)
    type(string), intent(in) :: list(:)
    integer, intent(in) :: n
    integer, allocatable :: idx(:), tmp(:)
    integer :: width, lo, mid, hi, a, b, k
    allocate(idx(n), tmp(n))
    do k = 1, n
      idx(k) = k
    end do
    width = 1
    do while (width < n)
      lo = 1
      do while (lo <= n)
        mid = min(lo + width - 1, n)
        hi = min(lo + 2 * width - 1, n)
        a = lo
        b = mid + 1
        do k = lo, hi
          if (a > mid) then
            tmp(k) = idx(b)
            b = b + 1
          else if (b > hi) then
            tmp(k) = idx(a)
            a = a + 1
          else if (llt(list(idx(b))%s, list(idx(a))%s)) then
            tmp(k) = idx(b)
            b = b + 1
          else
            tmp(k) = idx(a)
            a = a + 1
          end if
        end do
        lo = lo + 2 * width
      end do
      idx(1:n) = tmp(1:n)
      width = 2 * width
    end do
  end function sort_index

  ! position in sorted of the first entry named key, 0 if none
  integer function find_first(list, sorted_idx, n, key)
    type(string), intent(in) :: list(:)
    integer, intent(in) :: sorted_idx(:), n
    character(len=*), intent(in) :: key
    integer :: lo, hi, mid
    find_first = 0
    lo = 1
    hi = n
    do while (lo <= hi)
      mid = (lo + hi) / 2
      if (llt(list(sorted_idx(mid))%s, key)) then
        lo = mid + 1
      else
        if (list(sorted_idx(mid))%s == key) find_first = mid
        hi = mid - 1
      end if
    end do
  end function find_first

  logical function is_declared(path)
    character(len=*), intent(in) :: path
    is_declared = find_first(files, files_sorted, n_files, path) > 0
  end function is_declared

  ! ---- scanning ----

  recursive subroutine scan_file(owner, path, fixed_form, preprocessed, depth)
    integer, intent(in) :: owner, depth
    character(len=*), intent(in) :: path
    logical, intent(in) :: fixed_form, preprocessed
    character(len=:), allocatable :: line, more, text
    type(buffer) :: pending_text
    character :: quote
    integer :: unit, status, records, first, start
    logical :: fixed, switched, pending, continued, in_directive

    open(newunit=unit, file=path, status="old", action="read", iostat=status)
    if (status /= 0) then
      if (depth == 0) call die("cannot open " // path)
      return  ! an include that cannot be read: the compiler will say so
    end if
    fixed = fixed_form
    pending = .false.
    in_directive = .false.
    pending_text%n = 0
    quote = " "
    records = 0
    do
      call read_record(unit, line, status)
      if (status /= 0) exit
      records = records + 1
      if (records == 1) call strip_bom(line)
      call drop_cr(line)

      ! a directive, and the lines it continues with a trailing backslash
      if (in_directive) then
        in_directive = ends_in_backslash(line)
        cycle
      end if
      if (is_directive(line, fixed)) then
        in_directive = ends_in_backslash(line)
        call directive(owner, path, line, fixed, preprocessed, depth)
        cycle
      end if
      ! cpp joins a line that ends in a backslash with the next one
      if (preprocessed) then
        do while (ends_in_backslash(line))
          line = line(1:len_trim(line) - 1)
          call read_record(unit, more, status)
          if (status /= 0) exit
          call drop_cr(more)
          line = line // more
        end do
      end if

      if (fixed) then
        call expand_tab_field(line)
        call blank_out(line)
        if (len(line) > 0) then
          if (openmp .and. is_fixed_sentinel(line)) then
            line(1:2) = "  "
          else if (d_lines_as_code .and. scan(line(1:1), "dD") > 0) then
            line(1:1) = " "
          else if (scan(line(1:1), "cC*!%dD") > 0) then
            ! a comment line, maybe `!dir$ free`
            switched = fixed
            if (scan(line(1:1), "cC*!") > 0) call read_form_switch(line(2:), switched)
            if (switched .neqv. fixed) then
              if (pending) call statements(owner, path, pending_text%s(1:pending_text%n), fixed, preprocessed, depth)
              pending = .false.
              fixed = switched
            end if
            cycle
          end if
        end if
        if (fixed_line_length > 0 .and. len(line) > fixed_line_length) line = line(1:fixed_line_length)
        first = verify(line, " ")
        if (first == 0) cycle
        if (line(first:first) == "!" .and. first /= 6) cycle
        if (len(line) < 6) line = line // repeat(" ", 6 - len(line))
        ! a continuation (columns 1-5 blank, column 6 not blank or 0) is joined
        ! as is: blanks do not separate words in fixed form. otherwise columns
        ! 1-5 are the label and a new statement starts. letters there are no
        ! label: flang then reads the line from column 1, so do we
        start = 7
        if (verify(line(1:5), " 0123456789") /= 0) start = 1
        if (start == 1 .or. .not. (pending .and. line(1:5) == "" .and. line(6:6) /= " " .and. line(6:6) /= "0")) then
          if (pending) call statements(owner, path, pending_text%s(1:pending_text%n), fixed, preprocessed, depth)
          pending_text%n = 0
          quote = " "
          pending = .true.
        end if
        call append_code(pending_text, line(start:), quote, .false., continued)
      else
        call blank_out(line)
        if (openmp) call free_sentinel(line)
        first = verify(line, " ")
        if (first == 0) cycle
        if (line(first:first) == "!") then
          switched = fixed
          call read_form_switch(line(first + 1:), switched)
          if (.not. pending) fixed = switched
          cycle
        end if
        if (pending) then
          if (line(first:first) == "&") then
            text = line(first + 1:)
          else if (quote /= " ") then
            text = line
          else
            text = " " // line
          end if
        else
          pending_text%n = 0
          quote = " "
          text = line
        end if
        call append_code(pending_text, text, quote, .true., continued)
        pending = continued
        if (.not. pending) call statements(owner, path, pending_text%s(1:pending_text%n), fixed, preprocessed, depth)
      end if
    end do
    if (pending) call statements(owner, path, pending_text%s(1:pending_text%n), fixed, preprocessed, depth)
    close(unit)
  end subroutine scan_file

  ! dec tab format: a tab in columns 1-6 ends the label field; a digit 1-9
  ! after it is the continuation column
  subroutine expand_tab_field(line)
    character(len=:), allocatable, intent(inout) :: line
    character(len=:), allocatable :: label, rest
    integer :: t
    t = index(line(1:min(6, len(line))), achar(9))
    if (t == 0) return
    if (verify(line(1:t - 1), " 0123456789") /= 0) return
    label = line(1:t - 1)
    rest = line(t + 1:)
    if (len(rest) > 0) then
      if (scan(rest(1:1), "123456789") > 0) then
        line = label // repeat(" ", 5 - len(label)) // rest
        return
      end if
    end if
    line = label // repeat(" ", 6 - len(label)) // rest
  end subroutine expand_tab_field

  ! c$ / *$ / !$ in columns 1-2, then blanks or digits up to column 5
  logical function is_fixed_sentinel(line)
    character(len=*), intent(in) :: line
    is_fixed_sentinel = .false.
    if (len(line) < 2) return
    if (scan(line(1:1), "cC*!") == 0 .or. line(2:2) /= "$") return
    is_fixed_sentinel = verify(line(3:min(5, len(line))), " 0123456789") == 0
  end function is_fixed_sentinel

  ! free form `!$ ` or `!$&` starts an openmp conditional line, not `!$omp`
  subroutine free_sentinel(line)
    character(len=*), intent(inout) :: line
    integer :: p
    p = verify(line, " ")
    if (p == 0 .or. p + 1 > len(line)) return
    if (line(p:p + 1) /= "!$") return
    if (p + 2 <= len(line)) then
      if (line(p + 2:p + 2) /= " " .and. line(p + 2:p + 2) /= "&") return
    end if
    line(p:p + 1) = "  "
  end subroutine free_sentinel

  ! `dir$ fixed` / `dir$ free` (also dec$) after the comment character
  subroutine read_form_switch(text, fixed)
    character(len=*), intent(in) :: text
    logical, intent(inout) :: fixed
    character(len=:), allocatable :: low, rest
    low = lowered(trim(text))
    if (.not. (starts_with(low, "dir$") .or. starts_with(low, "dec$"))) return
    rest = after(low, 5)
    if (rest == "fixed") fixed = .true.
    if (rest == "free") fixed = .false.
  end subroutine read_form_switch

  ! appends the code of one line, up to a comment outside quotes. in free form
  ! a trailing & continues the statement
  subroutine append_code(statement_text, text, quote, free, continued)
    type(buffer), intent(inout) :: statement_text
    character(len=*), intent(in) :: text
    character, intent(inout) :: quote
    logical, intent(in) :: free
    logical, intent(out) :: continued
    integer :: k, cut, last
    cut = len(text) + 1
    do k = 1, len(text)
      if (quote == " ") then
        if (text(k:k) == "!") then
          cut = k
          exit
        else if (text(k:k) == "'" .or. text(k:k) == '"') then
          quote = text(k:k)
        end if
      else if (text(k:k) == quote) then
        quote = " "
      end if
    end do
    last = len_trim(text(1:cut - 1))
    continued = .false.
    if (free .and. last > 0) then
      if (text(last:last) == "&") then
        continued = .true.
        last = last - 1
      end if
    end if
    call append(statement_text, text(1:last))
  end subroutine append_code

  ! one logical line: its statements, split at `;` outside quotes
  recursive subroutine statements(owner, path, text, fixed, preprocessed, depth)
    integer, intent(in) :: owner, depth
    character(len=*), intent(in) :: path, text
    logical, intent(in) :: fixed, preprocessed
    character :: quote
    integer :: k, start
    quote = " "
    start = 1
    do k = 1, len(text)
      if (quote == " ") then
        if (text(k:k) == ";") then
          call statement(owner, path, text(start:k - 1), fixed, preprocessed, depth)
          start = k + 1
        else if (text(k:k) == "'" .or. text(k:k) == '"') then
          quote = text(k:k)
        end if
      else if (text(k:k) == quote) then
        quote = " "
      end if
    end do
    call statement(owner, path, text(start:), fixed, preprocessed, depth)
  end subroutine statements

  logical function is_procedure_word(name)
    character(len=*), intent(in) :: name
    is_procedure_word = starts_with(name, "procedure") .or. starts_with(name, "subroutine") .or. &
      starts_with(name, "function") .or. starts_with(name, "pure") .or. starts_with(name, "impure") .or. &
      starts_with(name, "elemental") .or. starts_with(name, "recursive") .or. &
      starts_with(name, "non_recursive") .or. starts_with(name, "simple")
  end function is_procedure_word

  recursive subroutine statement(owner, path, text, fixed, preprocessed, depth)
    integer, intent(in) :: owner, depth
    character(len=*), intent(in) :: path, text
    logical, intent(in) :: fixed, preprocessed
    character(len=:), allocatable :: original, low, rest, inside, tail, parent
    character :: quote
    integer :: n, close_at, colon, colons, first, last

    first = verify(text, " ")
    if (first == 0) return
    last = len_trim(text)
    ! a statement label
    n = verify(text(first:last), "0123456789") - 1
    if (n > 0 .and. n <= 5) then
      if (text(first + n:first + n) == " ") first = first + n + verify(text(first + n:last), " ") - 1
    end if
    ! module, submodule, use, include: nothing else needs a copy (a data
    ! statement can run over thousands of lines)
    if (scan(text(first:first), "msuiMSUI") == 0) return
    original = text(first:last)
    low = lowered(original)

    if (starts_with(low, "module") .and. len(low) > 6) then
      ! `module x` and nothing after it. `module procedure x`, `module function f()`
      ! and friends have more words and are not module statements
      rest = after(low, 7)
      n = name_length(rest)
      if (n == 0 .or. n < len(rest)) return
      ! the name can be glued to the keyword: fixed form ignores blanks, and flang
      ! reads free-form `module&` + `&x` as `module x`. glued, it can also be the
      ! next keyword (`moduleprocedure`)
      if (low(7:7) /= " " .and. is_procedure_word(rest)) return
      call add_provide(owner, rest, path)
    else if (starts_with(low, "submodule")) then
      ! submodule (parent) x   or   submodule (parent:ancestor) x
      rest = after(low, 10)
      if (.not. starts_with(rest, "(")) return
      close_at = index(rest, ")")
      if (close_at == 0) return
      inside = trim(adjustl(rest(2:close_at - 1)))
      rest = after(rest, close_at + 1)
      n = name_length(rest)
      if (n == 0) return
      colon = index(inside, ":")
      if (colon == 0) then
        call add_need(owner, inside)
        call add_provide(owner, inside // ":" // rest(1:n), path)
      else
        parent = trim(inside(1:colon - 1))
        call add_need(owner, parent)
        call add_need(owner, parent // ":" // after(inside, colon + 1))
        call add_provide(owner, parent // ":" // rest(1:n), path)
      end if
    else if (starts_with(low, "use")) then
      ! use x   use :: x   use, non_intrinsic :: x   (intrinsic ones are the compiler's)
      if (len(low) == 3) return
      if (scan(low(4:4), " ,:") == 0 .and. verify(low(4:4), "abcdefghijklmnopqrstuvwxyz_") /= 0) return
      rest = after(low, 4)
      if (starts_with(rest, ",")) then
        colons = index(rest, "::")
        if (colons == 0) return
        if (index(rest(1:colons), "intrinsic") > 0 .and. index(rest(1:colons), "non_intrinsic") == 0) return
        rest = after(rest, colons + 2)
      else if (starts_with(rest, "::")) then
        rest = after(rest, 3)
      else if (starts_with(rest, ":")) then
        return  ! a construct named use
      end if
      n = name_length(rest)
      if (n == 0) return
      ! only the name, or the name and its only/rename list. glued to the
      ! keyword (`usex`) it could be a variable in a list, so the list must
      ! look like one
      tail = after(rest, n + 1)
      if (len(tail) > 0) then
        if (tail(1:1) /= ",") return
        if (scan(low(4:4), " ,:") == 0 .and. .not. (starts_with(after(tail, 2), "only") .or. &
                                                    index(tail, "=>") > 0)) return
      end if
      call add_need(owner, rest(1:n))
    else if (starts_with(low, "include")) then
      ! include 'file', read in place in this file's form
      rest = after(original, 8)
      if (len(rest) < 3) return
      quote = rest(1:1)
      if (quote /= "'" .and. quote /= '"') return
      close_at = index(rest(2:), quote)
      if (close_at < 2) return
      if (len(after(rest, close_at + 2)) > 0) return
      call include_file(owner, path, rest(2:close_at), .true., fixed, preprocessed, depth)
    end if
  end subroutine statement

  ! #include "file" (searched next to the includer first) or #include <file>
  recursive subroutine directive(owner, path, line, fixed, preprocessed, depth)
    integer, intent(in) :: owner, depth
    character(len=*), intent(in) :: path, line
    logical, intent(in) :: fixed, preprocessed
    character(len=:), allocatable :: text, rest
    integer :: close_at
    text = after(line, index(line, "#") + 1)
    if (.not. starts_with(lowered(text), "include")) return
    rest = after(text, 8)
    if (len(rest) < 3) return
    if (rest(1:1) == '"') then
      close_at = index(rest(2:), '"')
      if (close_at < 2) return
      call include_file(owner, path, rest(2:close_at), .true., fixed, preprocessed, depth)
    else if (rest(1:1) == "<") then
      close_at = index(rest(2:), ">")
      if (close_at < 2) return
      call include_file(owner, path, rest(2:close_at), .false., fixed, preprocessed, depth)
    end if
  end subroutine directive

  ! reads an included file into the includer's source, if it is a declared file.
  ! an undeclared or missing one is skipped: the compile reports it
  recursive subroutine include_file(owner, includer, name, near_includer, fixed, preprocessed, depth)
    integer, intent(in) :: owner, depth
    character(len=*), intent(in) :: includer, name
    logical, intent(in) :: near_includer, fixed, preprocessed
    character(len=:), allocatable :: candidate
    integer :: k
    if (depth >= max_include_depth) return
    candidate = normalized(name)
    if (starts_with(candidate, "/") .or. index(candidate, ":") == 2) then
      if (is_declared(candidate)) call scan_file(owner, candidate, fixed, preprocessed, depth + 1)
      return
    end if
    if (near_includer) then
      candidate = normalized(join(dirname(includer), name))
      if (is_declared(candidate)) then
        call scan_file(owner, candidate, fixed, preprocessed, depth + 1)
        return
      end if
    end if
    do k = 1, n_include_dirs
      candidate = normalized(join(include_dirs(k)%s, name))
      if (is_declared(candidate)) then
        call scan_file(owner, candidate, fixed, preprocessed, depth + 1)
        return
      end if
    end do
  end subroutine include_file

  ! ---- ordering ----

  ! the source that provides a name: the asking source itself if it does
  ! (several sources can include one module file), else the first one; 0 if none
  integer function provider(name, asking)
    character(len=*), intent(in) :: name
    integer, intent(in) :: asking
    integer :: pos, k
    provider = 0
    pos = find_first(provide_name, provides_sorted, n_provides, name)
    if (pos == 0) return
    provider = provide_owner(provides_sorted(pos))
    do k = pos, n_provides
      if (provide_name(provides_sorted(k))%s /= name) exit
      if (provide_owner(provides_sorted(k)) == asking) then
        provider = asking
        return
      end if
    end do
  end function provider

  function where(p) result(text)
    integer, intent(in) :: p
    character(len=:), allocatable :: text
    text = srcs(provide_owner(p))%s
    if (provide_origin(p)%s /= text) text = text // " (in " // provide_origin(p)%s // ")"
  end function where

  ! one module defined in two places. the same included file read by two
  ! sources is one definition
  subroutine check_duplicates()
    integer :: k, j, first, other
    k = 1
    do while (k <= n_provides)
      first = provides_sorted(k)
      j = k + 1
      do while (j <= n_provides)
        other = provides_sorted(j)
        if (provide_name(other)%s /= provide_name(first)%s) exit
        if (provide_owner(other) /= provide_owner(first) .and. &
            provide_origin(other)%s /= provide_origin(first)%s) &
          call die("module '" // provide_name(first)%s // "' is defined by both " // &
                   where(first) // " and " // where(other))
        j = j + 1
      end do
      k = j
    end do
  end subroutine check_duplicates

  ! depth-first, without recursion: a source is emitted after the sources
  ! whose modules it needs
  subroutine order_sources()
    integer, allocatable :: stack(:), next(:)
    integer :: root, top, node, k, dependency
    allocate(state(n_srcs), sorted(n_srcs), stack(n_srcs), next(n_srcs))
    state = 0  ! 0 = not visited, 1 = on the stack, 2 = done
    do root = 1, n_srcs
      if (last_provide(root) < first_provide(root) .or. state(root) /= 0) cycle
      top = 1
      stack(1) = root
      next(1) = first_need(root)
      state(root) = 1
      do while (top > 0)
        node = stack(top)
        if (next(top) <= last_need(node)) then
          k = next(top)
          next(top) = k + 1
          dependency = provider(need_name(k)%s, node)
          if (dependency == 0 .or. dependency == node) cycle
          if (state(dependency) == 2) cycle
          if (state(dependency) == 1) call die_cycle(stack, top, dependency)
          top = top + 1
          stack(top) = dependency
          next(top) = first_need(dependency)
          state(dependency) = 1
        else
          state(node) = 2
          n_sorted = n_sorted + 1
          sorted(n_sorted) = node
          top = top - 1
        end if
      end do
    end do
  end subroutine order_sources

  subroutine die_cycle(stack, top, again)
    integer, intent(in) :: stack(:), top, again
    character(len=:), allocatable :: chain
    integer :: k, from
    from = 1
    do k = 1, top
      if (stack(k) == again) from = k
    end do
    chain = ""
    do k = from, top
      chain = chain // srcs(stack(k))%s // " -> "
    end do
    call die("modules depend on each other in a cycle: " // chain // srcs(again)%s)
  end subroutine die_cycle

  ! ---- output ----

  ! a response-file argument: always quoted, so blanks and quotes in a path
  ! survive, and never read as an option
  function quoted(path) result(text)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: text
    integer :: k
    text = '"'
    if (starts_with(path, "-")) text = text // "./"
    do k = 1, len(path)
      if (path(k:k) == '"' .or. path(k:k) == achar(92)) text = text // achar(92)
      text = text // path(k:k)
    end do
    text = text // '"'
  end function quoted

  subroutine write_outputs()
    integer :: unit, status, k
    ! valid code with nothing to warn about, so -pedantic -Werror is fine
    open(newunit=unit, file=empty_path, status="replace", action="write", iostat=status)
    if (status /= 0) call die("cannot write " // empty_path)
    write(unit, "(A)") "! written by rules_fortran: the module pass needs at least one source"
    write(unit, "(A)") "subroutine rules_fortran_module_pass_placeholder"
    write(unit, "(A)") "end subroutine rules_fortran_module_pass_placeholder"
    close(unit)

    open(newunit=unit, file=order_path, status="replace", action="write", iostat=status)
    if (status /= 0) call die("cannot write " // order_path)
    if (n_sorted == 0) write(unit, "(A)") quoted(empty_path)
    do k = 1, n_sorted
      write(unit, "(A)") quoted(srcs(sorted(k))%s)
    end do
    close(unit)
  end subroutine write_outputs

  ! for tests: what was read from each source
  subroutine dump()
    integer :: unit, status, s, k
    open(newunit=unit, file=dump_path, status="replace", action="write", iostat=status)
    if (status /= 0) call die("cannot write " // dump_path)
    do s = 1, n_srcs
      write(unit, "(A)") "S " // srcs(s)%s
      do k = first_provide(s), last_provide(s)
        write(unit, "(A)") "P " // provide_name(k)%s
      end do
      do k = first_need(s), last_need(s)
        write(unit, "(A)") "N " // need_name(k)%s
      end do
    end do
    close(unit)
  end subroutine dump

end program module_order
