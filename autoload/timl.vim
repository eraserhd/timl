" Maintainer:   Tim Pope <http://tpo.pe/>

if exists("g:autoloaded_timl")
  finish
endif
let g:autoloaded_timl = 1

" Section: Util {{{1

function! s:funcname(name) abort
  return substitute(a:name,'^s:',matchstr(expand('<sfile>'), '.*\zs<SNR>\d\+_'),'')
endfunction

function! s:function(name) abort
  return function(s:funcname(a:name))
endfunction

function! timl#freeze(...) abort
  return a:000
endfunction

function! timl#truth(val) abort
  return a:val isnot# g:timl#nil && a:val isnot# g:timl#false
endfunction

function! timl#identity(x) abort
  return a:x
endfunction

function! timl#key(key)
  if type(a:key) == type(0)
    return string(a:key)
  elseif timl#keywordp(a:key)
    return a:key[0]
  elseif a:key is# g:timl#nil
    return ' '
  else
    return ' '.timl#printer#string(a:key)
  endif
endfunction

function! timl#dekey(key)
  if a:key =~# '^#'
    throw 'timl: invalid key '.a:key
  elseif a:key ==# ' '
    return g:timl#nil
  elseif a:key =~# '^ '
    return timl#reader#read_string(a:key[1:-1])
  elseif a:key =~# '^[-+]\=\d'
    return timl#reader#read_string(a:key)
  else
    return timl#keyword(a:key)
  endif
endfunction

" }}}1
" Section: Munging {{{1

" From clojure/lang/Compiler.java
let s:munge = {
      \ '.': "#",
      \ ',': "_COMMA_",
      \ ':': "_COLON_",
      \ '+': "_PLUS_",
      \ '>': "_GT_",
      \ '<': "_LT_",
      \ '=': "_EQ_",
      \ '~': "_TILDE_",
      \ '!': "_BANG_",
      \ '@': "_CIRCA_",
      \ "'": "_SINGLEQUOTE_",
      \ '"': "_DOUBLEQUOTE_",
      \ '%': "_PERCENT_",
      \ '^': "_CARET_",
      \ '&': "_AMPERSAND_",
      \ '*': "_STAR_",
      \ '|': "_BAR_",
      \ '{': "_LBRACE_",
      \ '}': "_RBRACE_",
      \ '[': "_LBRACK_",
      \ ']': "_RBRACK_",
      \ '/': "_SLASH_",
      \ '\\': "_BSLASH_",
      \ '?': "_QMARK_"}

let s:demunge = {}
for s:key in keys(s:munge)
  let s:demunge[s:munge[s:key]] = s:key
endfor
unlet! s:key

function! timl#munge(var) abort
  let var = type(a:var) == type('') ? a:var : a:var[0]
  return tr(substitute(substitute(var, '[^[:alnum:]:#_-]', '\=get(s:munge,submatch(0), submatch(0))', 'g'), '_SLASH_\ze.', '#', ''), '-', '_')
endfunction

function! timl#demunge(var) abort
  let var = type(a:var) == type('') ? a:var : a:var[0]
  return tr(substitute(var, '_\(\u\+\)_', '\=get(s:demunge, submatch(0), submatch(0))', 'g'), '_', '-')
endfunction

" }}}1
" Section: Keywords {{{1

if !exists('s:keywords')
  let s:keywords = {}
endif

function! timl#keyword(str)
  if !has_key(s:keywords, a:str)
    let s:keywords[a:str] = {'0': a:str}
    lockvar s:keywords[a:str]
  endif
  return s:keywords[a:str]
endfunction

function! timl#keywordp(keyword)
  return type(a:keyword) == type({}) &&
        \ has_key(a:keyword, 0) &&
        \ type(a:keyword[0]) == type('') &&
        \ get(s:keywords, a:keyword[0], 0) is a:keyword
endfunction

function! timl#kw(kw)
  if !timl#keywordp(a:kw)
    throw 'timl: keyword expected but received '.timl#type#string(a:kw)
  endif
  return a:kw
endfunction

" }}}1
" Section: Type System {{{1

function! timl#bless(class, ...) abort
  return timl#type#bless(a:class, a:0 ? a:1 : {})
endfunction

if !exists('g:timl#nil')
  let g:timl#nil = timl#freeze()
  lockvar g:timl#nil
endif

function! timl#type(val) abort
  return timl#type#string(a:val)
endfunction

function! timl#persistentb(val) abort
  let val = a:val
  if islocked('val')
    throw "timl: persistent! called on an already persistent value"
  else
    lockvar 1 val
    return val
  endif
endfunction

function! timl#transient(val) abort
  let val = a:val
  if islocked('val')
    return copy(val)
  else
    throw "timl: transient called on an already transient value"
  endif
endfunction

function! timl#meta(obj) abort
  if timl#type#objectp(a:obj)
    return get(a:obj, '#meta', g:timl#nil)
  endif
  return g:timl#nil
endfunction

function! timl#with_meta(obj, meta) abort
  if timl#type#objectp(a:obj)
    if !timl#equalp(get(a:obj, '#meta', g:timl#nil), a:meta)
      let obj = copy(a:obj)
      if a:meta is# g:timl#nil
        call remove(obj, '#meta')
      else
        let obj['#meta'] = a:meta
      endif
      return timl#persistentb(obj)
    endif
    return a:obj
  endif
  throw 'timl: cannot attach metadata to a '.timl#type#string(a:obj)
endfunction

function! timl#str(val) abort
  if type(a:val) == type('')
    return a:val
  elseif type(a:val) == type(function('tr'))
    return substitute(join([a:val]), '[{}]', '', 'g')
  elseif timl#symbolp(a:val) || timl#keywordp(a:val)
    return a:val[0]
  elseif timl#consp(a:val)
    let _ = {'val': a:val}
    let acc = ''
    while !empty(_.val)
      let acc .= timl#str(timl#first(_.val)) . ','
      let _.val = timl#next(_.val)
    endwhile
    return acc
  elseif type(a:val) == type([])
    return join(map(copy(a:val), 'timl#str(v:val)'), ',').','
  else
    return string(a:val)
  endif
endfunction

let s:tint = type(0)
let s:tfloat = 5

function! timl#num(obj) abort
  if type(a:obj) == s:tint || type(a:obj) == s:tfloat
    return a:obj
  endif
  throw "timl: not a number"
endfunction

function! timl#int(obj) abort
  if type(a:obj) == s:tint
    return a:obj
  elseif type(a:obj) == s:tfloat
    return float2nr(a:obj)
  endif
  throw "timl: not a number"
endfunction

function! timl#float(obj) abort
  if type(a:obj) == s:tfloat
    return a:obj
  elseif type(a:obj) == s:tint
    return 0.0 + a:obj
  endif
  throw "timl: not a float"
endfunction

function! timl#equalp(x, ...) abort
  for y in a:000
    if type(a:x) != type(y) || a:x !=# y
      return 0
    endif
  endfor
  return 1
endfunction

" }}}1
" Section: Symbols {{{1

if !exists('s:symbols')
  let s:symbols = {}
endif

let s:symbol = timl#keyword('#timl.lang/Symbol')
function! timl#symbol(str)
  if !has_key(s:symbols, a:str)
    let s:symbols[a:str] = timl#bless(s:symbol, {'0': a:str})
    lockvar s:symbols[a:str]
  endif
  return s:symbols[a:str]
endfunction

function! timl#symbolp(symbol, ...)
  return type(a:symbol) == type({}) &&
        \ get(a:symbol, '#tag') is# s:symbol &&
        \ (a:0 ? a:symbol[0] ==# a:1 : 1)
endfunction

function! timl#sym(sym)
  if !timl#symbolp(a:sym)
    throw 'timl: symbol expected but received '.timl#type#string(a:sym)
  endif
  return a:sym
endfunction

function! timl#gensym(...)
  let s:id = get(s:, 'id', 0) + 1
  return timl#symbol((a:0 ? a:1 : 'G__').s:id)
endfunction

function! timl#name(val) abort
  if type(a:val) == type('')
    return a:val
  elseif timl#symbolp(a:val)
    return a:val[0]
  elseif timl#keywordp(a:val)
    return a:val[0]
  else
    throw "timl: no name for ".timl#type#string(a:val)
  endif
endfunction

runtime! autoload/timl/lang.vim

" }}}1
" Section: Collections {{{1

function! timl#collp(coll) abort
  return timl#type#canp(a:coll, g:timl#core#_conj)
endfunction

function! timl#into(coll, seq) abort
  let t = timl#type#string(a:coll)
  if a:coll is g:timl#nil
    return timl#seq(a:seq)
  elseif t ==# 'timl.vim/List'
    return timl#persistentb(extend(timl#transient(a:coll), timl#ary(a:seq)))
  elseif t ==# 'timl.lang/HashSet'
    let coll = timl#transient(a:coll)
    let _ = {}
    for _.v in timl#ary(a:seq)
      let coll[timl#key(_.v)] = _.v
    endfor
    return timl#persistentb(coll)
  elseif t ==# 'timl.lang/HashMap' || t ==# 'timl.vim/Dictionary'
    let coll = timl#transient(a:coll)
    let _ = {}
    for _.v in timl#ary(a:seq)
      call timl#assocb(coll, timl#ary(_.v))
    endfor
    return timl#persistentb(coll)
  else
    return call('timl#conj', [a:coll] + timl#ary(a:seq))
  endif
endfunction

function! timl#conj(coll, x, ...) abort
  let _ = {'coll': a:coll}
  for x in [a:x] + a:000
    let _.coll = timl#type#dispatch(g:timl#core#_conj, _.coll, x)
  endfor
  return _.coll
endfunction

function! timl#count(seq) abort
  let l:count = 0
  let _ = {'seq': a:seq}
  while _.seq isnot# g:timl#nil && !timl#type#canp(_.seq, g:timl#core#_count)
    let l:count += 1
    let _.seq = timl#next(_.seq)
  endwhile
  return l:count + (_.seq is# g:timl#nil ? 0 : timl#type#dispatch(g:timl#core#_count, _.seq))
endfunction

function! timl#containsp(coll, val) abort
  let sentinel = {}
  return timl#get(a:coll, a:val, sentinel) isnot# sentinel
endfunction

function! timl#mapp(coll)
  return timl#type#string(a:coll) == 'timl.lang/HashMap'
endfunction

function! timl#setp(coll)
  return timl#type#canp(a:coll, g:timl#core#_disj)
endfunction

function! timl#dictp(coll)
  return timl#type#string(a:coll) == 'timl.vim/Dictionary'
endfunction

function! timl#dict(...) abort
  let keyvals = a:0 == 1 ? a:1 : a:000
  if timl#mapp(keyvals)
    let _ = {'seq': timl#seq(keyvals)}
    let dict = {}
    while _.seq isnot# g:timl#nil
      let _.first = timl#first(_.seq)
      let dict[timl#str(_.first[0])] = _.first[1]
      let _.seq = timl#next(_.seq)
    endwhile
    return dict
  endif
  let dict = timl#assocb({}, keyvals)
  return dict
endfunction

let s:hash_map = timl#type#intern('timl.lang/HashMap')
function! timl#hash_map(...) abort
  let keyvals = a:0 == 1 ? a:1 : a:000
  let map = timl#bless(s:hash_map)
  if timl#dictp(keyvals)
    return timl#into(timl#persistentb(map), keyvals)
  endif
  call timl#assocb(map, keyvals)
  return timl#persistentb(map)
endfunction

let s:hash_set = timl#type#intern('timl.lang/HashSet')
function! timl#hash_set(...) abort
  return timl#set(a:000)
endfunction

function! timl#set(coll) abort
  let dict = timl#bless(s:hash_set)
  if type(a:coll) == type([])
    let _ = {}
    for _.val in a:coll
      let dict[timl#key(_.val)] = _.val
    endfor
    return timl#persistentb(dict)
  else
    throw 'not implemented'
  endif
endfunction

function! timl#assocb(coll, ...) abort
  let keyvals = a:0 == 1 ? timl#ary(a:1) : a:000
  if len(keyvals) % 2 == 0
    let type = timl#type#string(a:coll)
    for i in range(0, len(keyvals) - 1, 2)
      let key = (type == 'timl.vim/Dictionary' ? timl#str(keyvals[i]) : timl#key(keyvals[i]))
      let a:coll[key] = keyvals[i+1]
    endfor
    return a:coll
  endif
  throw 'timl: more keys than values'
endfunction

function! timl#assoc(coll, ...) abort
  let keyvals = a:0 == 1 ? a:1 : a:000
  let coll = timl#transient(a:coll)
  call timl#assocb(coll, keyvals)
  return timl#persistentb(coll)
endfunction

function! timl#dissocb(coll, ...) abort
  let _ = {}
  let t = timl#type#string(a:coll)
  for _.key in a:000
    let key = (t == 'timl.vim/Dictionary' ? timl#str(_.key) : timl#key(_.key))
    if has_key(a:coll, key)
      call remove(a:coll, key)
    endif
  endfor
  return a:coll
endfunction

function! timl#dissoc(coll, ...) abort
  return timl#persistentb(call('timl#dissocb', [timl#transient(a:coll)] + a:000))
endfunction

function! timl#disj(set, ...) abort
  let _ = {}
  let set = a:set
  for _.x in a:000
    let set = timl#type#dispatch(g:timl#core#_disj, set, _.x)
  endfor
  return set
endfunction

" }}}1
" Section: Lists {{{1

let s:cons = timl#type#intern('timl.lang/Cons')

let s:ary = type([])

function! timl#seq(coll) abort
  return timl#type#dispatch(g:timl#core#seq, a:coll)
endfunction

function! timl#seqp(coll) abort
  return timl#type#canp(a:coll, g:timl#core#seq)
endfunction

function! timl#first(coll) abort
  if timl#consp(a:coll)
    return a:coll.car
  elseif type(a:coll) == s:ary
    return get(a:coll, 0, g:timl#nil)
  elseif timl#type#canp(a:coll, g:timl#core#_first)
    return timl#type#dispatch(g:timl#core#_first, a:coll)
  else
    return timl#type#dispatch(g:timl#core#_first, timl#seq(a:coll))
  endif
endfunction

function! timl#rest(coll) abort
  if timl#consp(a:coll)
    return a:coll.cdr
  elseif timl#type#canp(a:coll, g:timl#core#_rest)
    return timl#type#dispatch(g:timl#core#_rest, a:coll)
  else
    let seq = timl#seq(a:coll)
    return seq is# g:timl#nil ? g:timl#empty_list : timl#type#dispatch(g:timl#core#_rest, seq)
  endif
endfunction

function! timl#next(coll) abort
  let rest = timl#rest(a:coll)
  return timl#seq(rest)
endfunction

function! timl#ffirst(seq) abort
  return timl#first(timl#first(a:seq))
endfunction

function! timl#fnext(seq) abort
  return timl#first(timl#next(a:seq))
endfunction

function! timl#nfirst(seq) abort
  return timl#next(timl#first(a:seq))
endfunction

function! timl#nnext(seq) abort
  return timl#next(timl#next(a:seq))
endfunction

function! timl#get(coll, key, ...) abort
  return timl#type#dispatch(g:timl#core#_lookup, a:coll, a:key, a:0 ? a:1 : g:timl#nil)
endfunction

function! timl#consp(obj) abort
  return type(a:obj) == type({}) && get(a:obj, '#tag') is# s:cons
endfunction

function! timl#list(...) abort
  return timl#list2(a:000)
endfunction

function! timl#cons(car, cdr) abort
  if timl#type#canp(a:cdr, g:timl#core#seq)
    let cons = timl#bless(s:cons, {'car': a:car, 'cdr': a:cdr})
    return timl#persistentb(cons)
  endif
  throw 'timl: not seqable'
endfunction

function! timl#list2(array)
  let _ = {'cdr': g:timl#empty_list}
  for i in range(len(a:array)-1, 0, -1)
    let _.cdr = timl#cons(a:array[i], _.cdr)
  endfor
  return _.cdr
endfunction

function! timl#vec(coll) abort
  if type(a:coll) ==# s:ary
    return a:coll is# g:timl#nil ? [] : a:coll
  endif
  let array = []
  let _ = {'seq': timl#seq(a:coll)}
  while _.seq isnot# g:timl#nil
    call add(array, timl#first(_.seq))
    let _.seq = timl#next(_.seq)
  endwhile
  return timl#persistentb(extend(array, _.seq))
endfunction

function! timl#ary(coll) abort
  return timl#vec(a:coll)
endfunction

function! timl#vectorp(obj) abort
  return type(a:obj) == type([]) && a:obj isnot# g:timl#nil
endfunction

" }}}1
" Section: Namespaces {{{1

let s:ns = timl#type#intern('timl.lang/Namespace')

function! timl#find_ns(name)
  return get(g:timl#namespaces, timl#str(a:name), g:timl#nil)
endfunction

function! timl#the_ns(name)
  if timl#type#string(a:name) ==# 'timl.lang/Namespace'
    return a:name
  endif
  let name = timl#str(a:name)
  if has_key(g:timl#namespaces, name)
    return g:timl#namespaces[name]
  endif
  throw 'timl: no such namespace '.name
endfunction

function! timl#create_ns(name, ...)
  let name = timl#sym(a:name)
  if !has_key(g:timl#namespaces, name[0])
    let g:timl#namespaces[name[0]] = timl#bless(s:ns, {'name': name, 'referring': [], 'aliases': {}})
  endif
  let ns = g:timl#namespaces[name[0]]
  if !a:0
    return ns
  endif
  let opts = a:1
  let _ = {}
  for _.refer in get(opts, 'referring', [])
    let sym = timl#sym(_.refer)
    if name !=# sym && index(ns.referring, sym) < 0
      call insert(ns.referring, sym)
    endif
  endfor
  for [_.name, _.target] in items(get(opts, 'aliases', {}))
    let ns.aliases[_.name] = timl#sym(_.target)
  endfor
  return ns
endfunction

" }}}1
" Section: Eval {{{1

let s:function_tag = timl#keyword('#timl.lang/Function')
let s:multifn_tag = timl#keyword('#timl.lang/MultiFn')
function! timl#call(Func, args, ...) abort
  if type(a:Func) == type(function('tr'))
    return call(a:Func, a:args, a:0 ? a:1 : {})
  elseif type(a:Func) == type({}) && get(a:Func, '#tag') is# s:function_tag
    return call(a:Func.call, (a:0 ? [a:1] : []) + a:args, a:Func)
  elseif type(a:Func) == type({}) && get(a:Func, '#tag') is# s:multifn_tag
    return call('timl#type#dispatch', [a:Func] + a:args)
  else
    return call('timl#type#dispatch', [g:timl#core#_invoke, a:Func] + (a:0 ? [a:1] : []) + a:args)
  endif
endfunction

function! s:lencompare(a, b)
  return len(a:b) - len(a:b)
endfunction

function! timl#ns_for_file(file) abort
  let file = fnamemodify(a:file, ':p')
  let candidates = []
  for glob in split(&runtimepath, ',')
    let candidates += filter(split(glob(glob), "\n"), 'file[0 : len(v:val)-1] ==# v:val && file[len(v:val)] =~# "[\\/]"')
  endfor
  if empty(candidates)
    return 'user'
  endif
  let dir = sort(candidates, s:function('s:lencompare'))[-1]
  let path = file[len(dir)+1 : -1]
  return substitute(tr(fnamemodify(path, ':r:r'), '\/_', '..-'), '^\%(autoload\|plugin\|test\).', '', '')
endfunction

function! timl#ns_for_cursor(...) abort
  let pattern = '\c(\%(in-\)\=ns\s\+''\=[[:alpha:]]\@='
  let line = 0
  if !a:0 || a:1
    let line = search(pattern, 'bcnW')
  endif
  if !line
    let i = 1
    while i < line('$') && i < 100
      if getline(i) =~# pattern
        let line = i
        break
      endif
      let i += 1
    endwhile
  endif
  if line
    let ns = matchstr(getline(line), pattern.'\zs[[:alnum:]._-]\+')
  else
    let ns = timl#ns_for_file(expand('%:p'))
  endif
  if !exists('g:autoloaded_timl_compiler')
    runtime! autoload/timl/compiler.vim
  endif
  if has_key(g:timl#namespaces, ns)
    return ns
  else
    return 'user'
  endif
endfunction

function! timl#build_exception(exception, throwpoint)
  let dict = {"exception": a:exception}
  let dict.line = +matchstr(a:throwpoint, '\d\+$')
  let dict.qflist = []
  if a:throwpoint !~# '^function '
    call add(dict.qflist, {"filename": matchstr(a:throwpoint, '^.\{-\}\ze\.\.')})
  endif
  for fn in split(matchstr(a:throwpoint, '\%( \|\.\.\)\zs.*\ze,'), '\.\.')
    call insert(dict.qflist, {'text': fn})
    if has_key(g:timl_functions, fn)
      let dict.qflist[0].filename = g:timl_functions[fn].file
      let dict.qflist[0].lnum = g:timl_functions[fn].line
    else
      try
        redir => out
        exe 'silent verbose function '.(fn =~# '^\d' ? '{'.fn.'}' : fn)
      catch
      finally
        redir END
      endtry
      if fn !~# '^\d'
        let dict.qflist[0].filename = expand(matchstr(out, "\n\tLast set from \\zs[^\n]*"))
        let dict.qflist[0].pattern = '^\s*fu\%[nction]!\=\s*'.substitute(fn,'^<SNR>\d\+_','s:','').'\s*('
      endif
    endif
  endfor
  return dict
endfunction

function! timl#eval(x, ...) abort
  return call('timl#compiler#eval', [a:x] + a:000)
endfunction

function! timl#re(str, ...) abort
  return call('timl#eval', [timl#reader#read_string(a:str)] + a:000)
endfunction

function! timl#rep(...) abort
  return timl#printer#string(call('timl#re', a:000))
endfunction

function! timl#source_file(filename)
  return timl#compiler#source_file(a:filename)
endfunction

if !exists('g:timl#requires')
  let g:timl#requires = {}
endif

function! timl#require(ns) abort
  let ns = timl#str(a:ns)
  if !has_key(g:timl#requires, ns)
    call timl#load(ns)
    let g:timl#requires[ns] = 1
  endif
  return g:timl#nil
endfunction

function! timl#load(ns) abort
  let base = tr(a:ns,'.-','/_')
  if !empty(findfile('autoload/'.base.'.vim', &rtp))
    execute 'runtime! autoload/'.base.'.vim'
    return g:timl#nil
  endif
  for file in findfile('autoload/'.base.'.tim', &rtp, -1)
    call timl#source_file(file)
    return g:timl#nil
  endfor
  throw 'timl: could not load '.a:ns
endfunction

" }}}1

" vim:set et sw=2:
