" vim: et sw=2 sts=2

scriptencoding utf-8

" Init: values {{{1
let s:delete_highlight = ['', 'SignifyLineDelete']

" Function: #get_next_id {{{1
function! sy#sign#get_next_id() abort
  let tmp = g:id_top
  let g:id_top += 1
  return tmp
endfunction

" Function: #get_current_signs {{{1
function! sy#sign#get_current_signs() abort
  let internal = {}
  let external = {}

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

    "echo 'DEBUG: '. s

    if type =~# '^Signify'
      " Handle ambiguous signs. Assume you have signs on line 3 and 4.
      " Removing line 3 would lead to the second sign to be shifted up
      " to line 3. Now there are still 2 signs, both one line 3.
      if has_key(internal, line)
        execute 'sign unplace' internal[line].id
      endif
      let internal[line] = { 'type': type, 'id': id }
    else
      let external[line] = id
    endif
  endfor

  return [internal, external]
endfunction

" Function: #update_signs {{{1
function! sy#sign#update_signs(hunks, signtable) abort
  let b:sy.hunks           = []
  let [internal, external] = sy#sign#get_current_signs()

  " Remove obsoleted signs.
  for line in filter(keys(internal), '!has_key(a:signtable, v:val)')
    execute 'sign unplace' internal[line].id
  endfor

  " Iterate over all new signs.
  for hunk in a:hunks
    " Internal data strucure kept for cursor jumps and debugging purposes.
    let syhunk = {
          \ 'ids'  : [],
          \ 'start': hunk[0].line,
          \ 'end'  : hunk[-1].line }

    for sign in hunk
      if has_key(external, sign.line)
        if has_key(internal, sign.line)
          " Remove Sy signs from lines with other signs.
          execute 'sign unplace' internal[sign.line].id
        endif
        continue
      elseif has_key(internal, sign.line)
        " There is a sign on this line already.
        if sign.type == internal[sign.line].type
          " Keep current sign since the new one has the same type.
          call add(syhunk.ids, internal[sign.line].id)
          continue
        else
          " Update sign by overwriting the ID of the current sign.
          let sign.id = internal[sign.line].id
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
  endfor
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
