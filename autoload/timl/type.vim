" Maintainer: Tim Pope <http://tpo.pe>

if exists("g:autoloaded_timl_type")
  finish
endif
let g:autoloaded_timl_type = 1

" Section: Blessing

if !exists('g:timl_tag_sentinel')
  let g:timl_tag_sentinel = ['blessed object']
  lockvar 1 g:timl_tag_sentinel
endif

if !exists('s:types')
  let s:types = {}
endif

function! timl#type#intern(type) abort
  if !has_key(s:types, a:type)
    let s:types[a:type] = [a:type]
    lockvar 1 s:types[a:type]
  endif
  return s:types[a:type]
endfunction

function! timl#type#constructor(_) dict abort
  if len(a:_) != len(self.slots)
    throw 'timl: arity error'
  endif
  let object = {}
  for i in range(len(a:_))
    let object[self.slots[i].name] = a:_[i]
  endfor
  return timl#type#bless(self.name.str, object)
endfunction

let s:type_type = timl#type#intern('timl.lang/Type')
function! timl#type#define(ns, var, slots) abort
  let type = timl#type#bless(s:type_type, {
        \ 'slots': a:slots,
        \ 'name': timl#symbol(a:ns.name.name . '/' . a:var.name),
        \ '__call__': function('timl#type#constructor')})
  return timl#namespace#intern(a:ns, a:var, type)
endfunction

let s:types = {
      \ 0: 'vim/Number',
      \ 1: 'vim/String',
      \ 2: 'vim/Funcref',
      \ 3: 'vim/List',
      \ 4: 'vim/Dictionary',
      \ 5: 'vim/Float'}

function! timl#type#objectp(obj) abort
  return type(a:obj) == type({}) && get(a:obj, '__flag__') is g:timl_tag_sentinel
endfunction

function! timl#type#string(val) abort
  let type = get(s:types, type(a:val), 'vim/Unknown')
  if a:val is# g:timl#nil
    return 'timl.lang/Nil'
  elseif type ==# 'vim/Dictionary'
    if get(a:val, '__flag__') is g:timl_tag_sentinel
      return a:val.__tag__[0]
    endif
  endif
  return type
endfunction

function! timl#type#keyword(val) abort
  return timl#keyword#intern(timl#type#string(a:val))
endfunction

let s:proto = {
      \ '__call__': function('timl#type#dispatch_call'),
      \ '__flag__': g:timl_tag_sentinel}
function! timl#type#bless(tag, ...) abort
  let obj = a:0 ? a:1 : {}
  call extend(obj, s:proto, 'keep')
  let obj.__tag__ = a:tag
  return obj
endfunction

function! timl#type#dispatch_call(_) dict
  return g:timl#core#call.__call__([self, a:_])
endfunction

" Section: Hierarchy
" Cribbed from clojure.core

function! timl#type#parents(key)
  return timl#set#coerce(values(get(g:timl_hierarchy.parents, timl#str(a:key), {})))
endfunction

function! timl#type#ancestors(key)
  return timl#set#coerce(values(get(g:timl_hierarchy.ancestors, timl#str(a:key), {})))
endfunction

function! timl#type#descendants(key)
  return timl#set#coerce(values(get(g:timl_hierarchy.descendants, timl#str(a:key), {})))
endfunction

function! s:tf(m, source, sources, target, targets)
  for k in [a:source] + values(get(a:sources, a:source[0], {}))
    if !has_key(a:targets, k[0])
      let a:targets[k[0]] = {}
    endif
    let a:targets[k[0]][a:target[0]] = a:target
    for j in values(get(a:targets, a:target[0], {}))
      let a:targets[k[0]][j[0]] = j
    endfor
  endfor
endfunction

function! s:isap(tag, parent)
  return a:tag ==# a:parent || has_key(get(g:timl_hierarchy.ancestors, a:tag, {}), a:parent)
endfunction

function! timl#type#isap(tag, parent)
  return timl#keyword#cast(a:tag) is# timl#keyword#cast(a:parent)
        \ || has_key(get(g:timl_hierarchy.ancestors, a:tag[0], {}), a:parent[0])
endfunction

function! timl#type#derive(tag, parent)
  let tp = g:timl_hierarchy.parents
  let td = g:timl_hierarchy.descendants
  let ta = g:timl_hierarchy.ancestors
  let tag = timl#keyword#cast(a:tag)
  let parent = timl#keyword#cast(a:parent)
  if !has_key(tp, tag[0])
    let tp[tag[0]] = {}
  endif
  if !has_key(tp[tag[0]], parent[0])
    if has_key(get(ta, tag[0], {}), parent[0])
      throw "timl#type: :".tag[0]." already has :".parent[0]." as ancestor"
    endif
    if has_key(get(ta, parent[0], {}), tag[0])
      throw "timl#type: :".parent[0]." has :".tag[0]." as ancestor"
    endif
    let tp[tag[0]][parent[0]] = parent
    call s:tf(ta, tag, td, parent, ta)
    call s:tf(td, parent, ta, tag, td)
  endif
  let g:timl_hierarchy = copy(g:timl_hierarchy) " expire caches
  return g:timl_hierarchy
endfunction

" Section: Dispatch

function! timl#type#canp(obj, this)
  return s:get_method(a:this, timl#type#string(a:obj)) isnot# g:timl#nil
endfunction

function! s:get_method(this, type)
  if a:this.hierarchy isnot# g:timl_hierarchy
    let a:this.cache = {}
    let a:this.hierarchy = g:timl_hierarchy
  endif
  if !has_key(a:this.cache, a:type)
    let _ = {'preferred': g:timl#nil}
    for [_.type, _.fn] in items(a:this.methods)
      if s:isap(a:type, _.type)
        if _.preferred is g:timl#nil || s:isap(_.type, _.preferred[0])
          let _.preferred = [_.type, _.fn]
        elseif !s:isap(_.preferred[0], _.type)
          throw 'timl#type: ambiguous'
        endif
      endif
    endfor
    if _.preferred is# g:timl#nil
      let a:this.cache[a:type] = get(a:this.methods, timl#map#key(g:timl#nil), g:timl#nil)
    else
      let a:this.cache[a:type] = _.preferred[1]
    endif
  endif
  return get(a:this.cache, a:type, g:timl#nil)
endfunction

let s:t_function = type(function('tr'))
let s:t_dict = type({})
function! timl#type#apply(_) dict abort
  let type = timl#type#string(a:_[0])
  if self.hierarchy isnot# g:timl_hierarchy
    let self.cache = {}
    let self.hierarchy = g:timl_hierarchy
  endif
  let Dispatch = has_key(self.cache, type) ? self.cache[type] : s:get_method(self, type)
  let t = type(Dispatch)
  if t == s:t_function
    return call(Dispatch, a:_)
  elseif t == s:t_dict
    return Dispatch.__call__(a:_)
  endif
  throw 'timl#type: no '.self.ns.name[0].'/'.self.name[0].' dispatch for '.type
endfunction

function! timl#type#dispatch(this, _) abort
  return call('timl#type#apply', [a:_], a:this)
endfunction

" Section: Method Creation

let s:multifn_type = timl#type#intern('timl.lang/MultiFn')
function! timl#type#define_method(ns, name, type, fn) abort
  let var = timl#namespace#maybe_resolve(a:ns, timl#symbol#cast(a:name))
  if var is# g:timl#nil || timl#type#string(g:{var.munged}) isnot# 'timl.lang/MultiFn'
    unlet var
    if !empty(a:name.namespace)
      throw "timl: no such method ".a:name.str
    endif
    let fn = timl#type#bless(s:multifn_type, {
          \ '__call__': function('timl#type#apply'),
          \ 'ns': a:ns,
          \ 'name': a:name,
          \ 'cache': {},
          \ 'hierarchy': g:timl_hierarchy,
          \ 'methods': {}})
    let var = timl#namespace#intern(a:ns, a:name, fn)
  endif
  let multi = g:{var.munged}
  let multi.methods[a:type is# g:timl#nil ? ' ' : timl#str(a:type)] = a:fn
  let multi.cache = {}
  return var
endfunction

" Section: Initialization

if !exists('g:timl_hierarchy')
  let g:timl_hierarchy = {'parents': {}, 'descendants': {}, 'ancestors': {}}
  call timl#type#derive(timl#keyword#intern('vim/Number'), timl#keyword#intern('vim/Numeric'))
  call timl#type#derive(timl#keyword#intern('vim/Float'), timl#keyword#intern('vim/Numeric'))
endif

" vim:set et sw=2:
