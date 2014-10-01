" vim: et sw=2 sts=2

scriptencoding utf-8

" Init: values {{{1
let s:sign_delete      = get(g:, 'signify_sign_delete', '_')
let s:delete_highlight = ['', 'SignifyLineDelete']

" Function: #get_next_id {{{1
function! sy#sign#get_next_id() abort
  let tmp = g:id_top
  let g:id_top += 1
  return tmp
endfunction

" Function: #get_current_signs {{{1
function! sy#sign#get_current_signs() abort
  let g:internal = {}
  let g:external = {}

  let lang = v:lang
  silent! execute 'language message C'
  redir => signlist
    silent! execute 'sign place buffer='. b:sy.buffer
  redir END
  silent! execute 'language message' lang

  for signline in split(signlist, '\n')[2:]
    let tokens = matchlist(signline, '\v^\s+line\=(\d+)\s+id\=(\d+)\s+name\=(.*)$')
    let line   = str2nr(tokens[1])
    let id     = str2nr(tokens[2])
    let type   = tokens[3]

    if type =~# '^Signify'
      " Handle ambiguous signs. Assume you have signs on line 3 and 4.
      " Removing line 3 would lead to the second sign to be shifted up
      " to line 3. Now there are still 2 signs, both one line 3.
      if has_key(g:internal, line)
        execute 'sign unplace' g:internal[line].id
      endif
      let g:internal[line] = { 'type': type, 'id': id }
    else
      let g:external[line] = id
    endif
  endfor
endfunction


" Function: #process_diff {{{1
function! sy#sign#process_diff(diff) abort
  let [added, modified, deleted] = [0, 0, 0]
  let hunks                      = []
  let b:sy.hunks                 = []
  let signtable                  = {}

  " XXX: update g:internal / g:external
  call sy#sign#get_current_signs()

  " Determine where we have to put our signs.
  for line in filter(split(a:diff, '\n'), 'v:val =~ "^@@ "')
    let hunk = []

    let tokens = matchlist(line, '^@@ -\v(\d+),?(\d*) \+(\d+),?(\d*)')

    let old_line = str2nr(tokens[1])
    let new_line = str2nr(tokens[3])

    let old_count = empty(tokens[2]) ? 1 : str2nr(tokens[2])
    let new_count = empty(tokens[4]) ? 1 : str2nr(tokens[4])

    " 2 lines added:

    " @@ -5,0 +6,2 @@ this is line 5
    " +this is line 5
    " +this is line 5

    if (old_count == 0) && (new_count >= 1)
      let offset = 0

      while offset < new_count
        let line    = new_line + offset
        let offset += 1
        if s:external_sign_present(line)
          continue
        endif
        let added          += 1
        let signtable[line] = 1
        call add(hunk, {
              \ 'id'  : sy#sign#get_next_id(),
              \ 'type': 'SignifyAdd',
              \ 'line': line })
      endwhile

    " 2 lines removed:

    " @@ -6,2 +5,0 @@ this is line 5
    " -this is line 6
    " -this is line 7

    elseif (old_count >= 1) && (new_count == 0)
      if s:external_sign_present(new_line)
        continue
      endif

      let deleted += old_count

      if new_line == 0
        let signtable.1 = 1
        call add(hunk, {
              \ 'id'  : sy#sign#get_next_id(),
              \ 'type': 'SignifyRemoveFirstLine',
              \ 'line': 1 })
      elseif old_count <= 99
        let signtable[new_line] = 1
        call add(hunk, {
              \ 'id'  : sy#sign#get_next_id(),
              \ 'type': 'SignifyDelete'. old_count,
              \ 'text': substitute(s:sign_delete . old_count, '.*\ze..$', '', ''),
              \ 'line': new_line })
      else
        let signtable[new_line] = 1
        call add(hunk, {
              \ 'id'  : sy#sign#get_next_id(),
              \ 'type': 'SignifyDeleteMore',
              \ 'line': new_line,
              \ 'text': s:sign_delete .'>' })
      endif

    " 2 lines changed:

    " @@ -5,2 +5,2 @@ this is line 4
    " -this is line 5
    " -this is line 6
    " +this os line 5
    " +this os line 6

    elseif old_count == new_count
      let modified += old_count
      let offset    = 0

      while offset < new_count
        let line    = new_line + offset
        let offset += 1
        if s:external_sign_present(line)
          continue
        endif
        let signtable[line] = 1
        call add(hunk, {
              \ 'id'  : sy#sign#get_next_id(),
              \ 'type': 'SignifyChange',
              \ 'line': line })
      endwhile
    else

      " 2 lines changed; 2 lines deleted:

      " @@ -5,4 +5,2 @@ this is line 4
      " -this is line 5
      " -this is line 6
      " -this is line 7
      " -this is line 8
      " +this os line 5
      " +this os line 6

      if old_count > new_count
        let modified += new_count
        let removed   = (old_count - new_count)
        let deleted  += removed
        let offset    = 0

        while offset < (new_count - 1)
          let line    = new_line + offset
          let offset += 1
          if s:external_sign_present(line)
            continue
          endif
          let signtable[line] = 1
          call add(hunk, {
                \ 'id'  : sy#sign#get_next_id(),
                \ 'type': 'SignifyChange',
                \ 'line': line })
        endwhile

        if s:external_sign_present(new_line)
          continue
        endif
        let signtable[new_line] = 1
        call add(hunk, {
              \ 'id'  : sy#sign#get_next_id(),
              \ 'type': (removed > 9) ? 'SignifyChangeDeleteMore' : 'SignifyChangeDelete'. removed,
              \ 'line': new_line })

      " lines changed and added:

      " @@ -5 +5,3 @@ this is line 4
      " -this is line 5
      " +this os line 5
      " +this is line 42
      " +this is line 666

      else
        let modified += old_count
        let offset    = 0

        while offset < old_count
          let line    = new_line + offset
          let offset += 1
          if s:external_sign_present(line)
            continue
          endif
          let added          += 1
          let signtable[line] = 1
          call add(hunk, {
                \ 'id'  : sy#sign#get_next_id(),
                \ 'type': 'SignifyChange',
                \ 'line': line })
        endwhile

        while offset < new_count
          let line    = new_line + offset
          let offset += 1
          if s:external_sign_present(line)
            continue
          endif
          let signtable[line] = 1
          call add(hunk, {
                \ 'id'  : sy#sign#get_next_id(),
                \ 'type': 'SignifyAdd',
                \ 'line': line })
        endwhile
      endif
    endif

    if !empty(hunk)
      " internal data strucure kept for cursor jumps and debugging purposes.
      let syhunk = {
            \ 'ids'  : [],
            \ 'start': hunk[0].line,
            \ 'end'  : hunk[-1].line }

      for sign in hunk
        if has_key(g:internal, sign.line)
          " There is a sign on this line already.
          if sign.type == g:internal[sign.line].type
            " Keep current sign since the new one has the same type.
            call add(syhunk.ids, g:internal[sign.line].id)
            continue
          else
            " Update sign by overwriting the ID of the current sign.
            let sign.id = g:internal[sign.line].id
          endif
        endif

        if sign.type =~# 'SignifyDelete'
          execute printf('sign define %s text=%s texthl=SignifySignDelete linehl=%s',
                \ sign.type,
                \ sign.text,
                \ s:delete_highlight[g:signify_line_highlight])
        endif
        execute printf('sign place %d line=%d name=%s buffer=%s',
              \ sign.id,
              \ sign.line,
              \ sign.type,
              \ b:sy.buffer)

        call add(syhunk.ids, sign.id)
      endfor

      call add(b:sy.hunks, syhunk)
    endif
  endfor

  " Remove obsoleted signs.
  for line in filter(keys(g:internal), '!has_key(signtable, v:val)')
    execute 'sign unplace' g:internal[line].id
  endfor

  let b:sy.stats = [added, modified, deleted]
endfunction

function! s:external_sign_present(line) abort
  if has_key(g:external, a:line)
    if has_key(g:internal, a:line)
      " Remove Sy signs from lines with other signs.
      execute 'sign unplace' g:internal[a:line].id
    endif
    return 1
  endif
endfunction

" Function: #remove_all_signs {{{1
function! sy#sign#remove_all_signs() abort
  for hunk in b:sy.hunks
    for id in hunk.ids
      execute 'sign unplace' id
    endfor
  endfor

  let b:sy.hunks = []
  let b:sy.stats = [0, 0, 0]
endfunction
