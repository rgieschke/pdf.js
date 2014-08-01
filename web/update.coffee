###
Copyright 2014 Rafael Gieschke

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
###

# ISO 32000-1:2008 is at <http://www.adobe.com/devnet/pdf/pdf_reference.html>,
# <http://www.adobe.com/content/dam/Adobe/en/devnet/acrobat/pdfs/PDF32000_2008.pdf>.

Buffer = (size = 1024) ->
  @array = new Uint8Array(size)
  @length = 0

Buffer.prototype =
  ensureAvailable: (length) ->
    neededSize = @length + length
    newSize = @array.byteLength
    if neededSize <= newSize
      return
    while neededSize > newSize
      newSize *= 2
    arrayNew = new Uint8Array(newSize)
    arrayNew.set(@getArray(), 0)
    @array = arrayNew
    return

  writeArray: (array) ->
    array = array.getArray() if array instanceof Buffer
    @ensureAvailable(array.byteLength)
    @array.set(array, @length)
    @length += array.byteLength
    return

  writeNumBigEndian: (num, numBytes = 1) ->
    # TODO: Code for Num > Math.pow(2, 31) - 1 (= 2147483647).
    # Num should still be < Math.pow(2, 53).
    if numBytes*8 > 32
      throw new Error("NumBytes is too large.")
    if num < 0
      throw new Error("Num must not be negative.")
    if num > Math.pow(2, numBytes*8) - 1
      throw new Error("Num is too large.")
    @ensureAvailable(numBytes)
    for i in [(numBytes-1)..0]
      @array[@length++] = (num >>> i*8) & 0xff
    return

  writeStringLatin1: (str) ->
    @ensureAvailable(str.length)
    for _, i in str
      @array[@length++] = str.charCodeAt(i)
    return

  getByteLength: () ->
    @length

  getArray: () ->
    @array.subarray(0, @length)

values = (obj) ->
  (v for _, v of obj)

group = (constArray, sortFunc, groupFunc) ->
  array = constArray.slice(0)
  array.sort(sortFunc)
  if array.length == 0
    return []
  groups = []
  curGroup = [array.shift()]
  for v in array
    if groupFunc(v, curGroup)
      curGroup.push(v)
    else
      groups.push(curGroup)
      curGroup = [v]
  groups.push(curGroup)
  return groups

pad = (num, length) ->
  str = "#{num}"
  while str.length < length
    str = "0#{str}"
  return str

toHex = (str) ->
  (pad(str.charCodeAt(i).toString(16), 2) for _, i in str).join("")

isDict = (obj) ->
  (typeof obj == "object") && ("map" of obj) && !isArray(obj)

isArray = (obj) ->
  (typeof obj == "object") && (obj instanceof Array)

isRef = (obj) ->
  (typeof obj == "object") && ("num" of obj)

genObjId = (ref) ->
  "R#{ref.num}.#{ref.gen}"

PdfObjectManager = () ->
  @objects = {}
  @dirty = {}
  @pdfWriter = new PdfWriter()
  @basePdfDocument = null
  return

PdfObjectManager.prototype =
  setBaseDocumentPromise: (@basePdfDocument) ->
    @basePdfDocument.getDownloadInfo().then (info) =>
      @pdfWriter.globalOffset = info.length
      @getTrailerPromise()
    .then (trailer) =>
      @pdfWriter.trailer = trailer
      @pdfWriter.nextNum = trailer.map.Size
      @pdfWriter.trailer.map.Prev = @basePdfDocument.pdfInfo.startXRef
      return

  writeUpdated: () ->
    for _, v of @dirty
      @pdfWriter.writeObj(v.ref, v.val)
    @dirty = {}
    return @

  update: (ref, val) ->
    id = genObjId(ref)
    @objects[id] = val
    @dirty[id] = { ref: ref, val: val }
    return @

  getTrailerPromise: () ->
    @getPromise("trailer")

  getPromise: (ref) ->
    objId = genObjId(ref)
    if objId of @objects
      return Promise.resolve(@objects[objId])
    @basePdfDocument.transport.getRawObject(ref).then (obj) =>
      if objId of @objects
        return @objects[objId]
      if isDict(obj)
        obj = new PdfDict(obj, null, ref, @)
      @objects[objId] = obj
      return obj

  createObjectURLPromise: () ->
    @writeUpdated()
    @pdfWriter.endFile()
    @basePdfDocument.transport.getData().then (data) =>
      blob = new Blob([data, @pdfWriter.out.getArray()], {type: "application/pdf"})
      return URL.createObjectURL(blob)

PdfDict = (obj, @topDict=@, @ref, @manager) ->
  @map = obj.map
  return

PdfDict.prototype =
  update: () ->
    @topDict.manager.update(@topDict.ref, @topDict)

  has: (key) ->
    key of @map

  getRaw: (key) ->
    @map[key]

  getPromise: (key) ->
    unless key of @map
      return Promise.reject(new Error("Key not found."))
    subObj = @map[key]
    if isRef(subObj)
      return @topDict.manager.getPromise(subObj)
    if isDict(subObj)
      return Promise.resolve(new PdfDict(subObj, @))
    return Promise.resolve(subObj)

  set: (key, val) ->
    subObj = @map[key]
    if isRef(subObj)
      newObj = new PdfDict(val, null, subObj, @topDict.manager)
      newObj.update()
      return @
    else
      @map[key] = val
      @.update()
      return @

PdfWriter = () ->
  @out = new Buffer()
  @globalOffset = 0
  @nextNum = 1
  @offsets = {}
  # TODO: Some implementations preset @offsets with
  # @offsets = { "R0.65535": { offset: 0, num: 0, gen: 65535, free: true } }
  # but we should not have to do this unless we fiddle with
  # the free entries list and only want to update PDF files.
  # TODO: Code for creatining new PDF files, including %PDF-...
  @trailer = null
  @startXRef = 0
  return

PdfWriter.prototype =
  createRef: () ->
    { num: @nextNum++, gen: 0 }

  write: (str) ->
    @out.writeStringLatin1(str)

  writeArray: (array) ->
    @out.writeArray(array)

  writeObj: (ref, obj, stream) ->
    @offsets[genObjId(ref)] =
      num: ref.num
      gen: ref.gen
      free: false
      offset: @out.length + @globalOffset
    @write("#{ref.num} #{ref.gen} obj\n#{serialize(obj)}\n")
    if stream?
      @write("stream\n")
      @writeArray(stream)
      @write("\nendstream\n")
    @write("endobj\n")

  endFile : () ->
    if @trailer.map.Type?.name == "XRef"
      console.log("Writing XRefStream.")
      @writeXRefStream()
    else
      console.log("Writing XRefTable.")
      @writeXRefTable()

  writeXRefStream: () ->
    # Cf. ISO 32000-1:2008, 7.5.8 Cross-Reference Streams.
    stream = new Buffer()
    W = [1, 4, 2]
    obj = { map: { Type: {name: "XRef"}, Index: [], W: W } }
    objRef = @createRef()
    # Copy entries from original cross-reference stream dictionary.
    for key, val of @trailer.map
      unless key in ["Type", "Index", "W", "Filter", "DecodeParms"]
        obj.map[key] = val
    groups = group values(@offsets),
      (a, b) -> a.num - b.num,
      (v, group) -> group[group.length - 1].num + 1 == v.num
    for g in groups
      obj.map.Index.push(g[0].num, g.length)
      for entry in g
        if entry.free
          stream.writeNumBigEndian(0, W[0])
          stream.writeNumBigEndian(entry.num, W[1])
          stream.writeNumBigEndian(entry.gen, W[2])
        else
          stream.writeNumBigEndian(1, W[0])
          stream.writeNumBigEndian(entry.offset, W[1])
          stream.writeNumBigEndian(entry.gen, W[2])
    obj.map.Size = @nextNum
    obj.map.Length = stream.getByteLength()
    @startXRef = @out.length + @globalOffset
    @writeObj(objRef, obj, stream)
    @write("startxref\n#{@startXRef}\n")
    @write("%%EOF\n")

  writeXRefTable: () ->
    # Cf. ISO 32000-1:2008, 7.5.4 Cross-Reference Table.
    res = ""
    groups = group values(@offsets),
      (a, b) -> a.num - b.num,
      (v, group) -> group[group.length - 1].num + 1 == v.num
    for g in groups
      res += "#{g[0].num} #{g.length}\n"
      for entry in g
        res += "#{pad(entry.offset, 10)} #{pad(entry.gen, 5)}" +
        " #{if entry.free then "f" else "n"}\n"
    @startXRef = @out.length + @globalOffset
    @write("xref\n")
    @write(res)
    @trailer.map.Size = @nextNum
    @write("trailer\n")
    @write(serialize(@trailer))
    @write("startxref\n#{@startXRef}\n")
    @write("%%EOF\n")

serialize = (obj) ->
  if typeof obj in ["boolean", "number"] || obj == null
    return "#{obj}"
  if typeof obj == "string"
    # This is the minimal set of special chars in a literal string
    # (cf. ISO 32000-1:2008 7.3.4.2).
    if /[()\\\r]/.test(obj)
      return "<#{toHex(obj)}>"
    else
      return "(#{obj})"
  if typeof obj != "object"
    throw new Error("Cannot serialize.")
  if "name" of obj
    return "/#{obj.name}"
  if obj.hasOwnProperty("map") # Array has map in prototype!
    return "<<\n#{ ( "/#{k} #{serialize(v)}" for k, v of obj.map).join("\n") }\n>>"
  if obj instanceof Array
    return "[ #{ (serialize(v) for v in obj).join(" ") }]"
  if "dict" of obj # Stream.
    return new Error("Cannot serialize streams yet.") # TODO.
  if "num" of obj # Ref.
    return "#{obj.num} #{obj.gen} R"
  throw new Error("Cannot serialize.")

##################################################

# Helpers.
window.Promise.prototype.in = (varName) ->
  @then (data) ->
    window[varName] = data
  .catch (error) ->
    window[varName] = { PromiseRejected: error }

window.openArray = (array) ->
  window.open(getBlob(array))

window.getBlob = getBlob = (array) ->
  blob = new Blob([array])
  return window.URL.createObjectURL(blob)

window.addEventListener "load", () ->
  div = document.createElement("div")
  div.style.position = "fixed"
  div.style.top = "35px"
  div.style.right = "20px"
  div.style.width = "100px"
  div.style.height = "100px"
  div.style.background = "white"
  div.style.padding = "5px"
  div.style.boxShadow = "1px 3px 5px black"
  document.body.appendChild(div)
  div.innerHTML =
    "<a href='javascript:deleteFirstPage();void(0)'>Delete first page!</a>"
  window.outputDiv = div

window.deleteFirstPage = () ->
  window.pdfManager = pdf = new PdfObjectManager()
  new () ->
    pdf.setBaseDocumentPromise(PDFView.pdfDocument).then () ->
      pdf.getTrailerPromise()
    .then (trailer) ->
      trailer.getPromise("Root")
    .then (root) ->
      console.log root
      root.getPromise("Pages")
    .then findFirst = (pages) =>
      if isDict(pages) && pages.has("Kids")
        @lastPages = pages
        @lastPages.set("Count", @lastPages.map.Count - 1)
        return pages.getPromise("Kids").then(findFirst)
      if isArray(pages)
        @lastPagesArray = pages
        return pdf.getPromise(pages[0]).then(findFirst)
      else
        return {@lastPages, @lastPagesArray}
    .then (res) ->
      res.lastPagesArray.shift()
      res.lastPages.set("Kids", res.lastPagesArray)
      console.log res
    .then () ->
      pdf.createObjectURLPromise()
    .then (url) ->
      window.outputDiv.innerHTML += " <a href='#{url}'>Generated PDF</a>"
    .catch (err) ->
      window.outputDiv.innerHTML += " ERROR: #{err}"
