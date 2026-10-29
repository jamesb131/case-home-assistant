// Android Things ships an older WebView, so provide the small set of modern
// built-ins CASE uses before React starts.
if (!Promise.allSettled) {
  Promise.allSettled = function allSettled(iterable) {
    return Promise.all(
      Array.from(iterable).map((item) =>
        Promise.resolve(item).then(
          (value) => ({ status: 'fulfilled', value }),
          (reason) => ({ status: 'rejected', reason }),
        ),
      ),
    )
  }
}

if (!Object.fromEntries) {
  Object.fromEntries = function fromEntries(iterable) {
    const result = {}
    Array.from(iterable).forEach((entry) => {
      if (!entry || entry.length < 2) {
        throw new TypeError('Iterator value is not an entry object')
      }
      result[entry[0]] = entry[1]
    })
    return result
  }
}

if (!String.prototype.replaceAll) {
  Object.defineProperty(String.prototype, 'replaceAll', {
    configurable: true,
    writable: true,
    value(search, replacement) {
      const source = String(this)
      if (search instanceof RegExp) {
        if (!search.global) {
          throw new TypeError('replaceAll requires a global regular expression')
        }
        return source.replace(search, replacement)
      }

      const needle = String(search)
      if (needle === '') {
        const parts = source.split('')
        const values = parts.map((character, index) => {
          const prefix = typeof replacement === 'function'
            ? replacement('', index, source)
            : String(replacement)
          return `${prefix}${character}`
        })
        const suffix = typeof replacement === 'function'
          ? replacement('', source.length, source)
          : String(replacement)
        return `${values.join('')}${suffix}`
      }

      if (typeof replacement !== 'function') {
        return source.split(needle).join(String(replacement))
      }

      let output = ''
      let cursor = 0
      let index = source.indexOf(needle)
      while (index !== -1) {
        output += source.slice(cursor, index)
        output += replacement(needle, index, source)
        cursor = index + needle.length
        index = source.indexOf(needle, cursor)
      }
      return output + source.slice(cursor)
    },
  })
}
