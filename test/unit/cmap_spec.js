/* -*- Mode: Java; tab-width: 2; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set shiftwidth=2 tabstop=2 autoindent cindent expandtab: */
/* globals expect, it, describe, StringStream, CMapFactory, Name */

'use strict';

describe('cmap', function() {
  it('parses beginbfchar', function() {
    var str = '2 beginbfchar\n' +
              '<03> <00>\n' +
              '<04> <01>\n' +
              'endbfchar\n';
    var stream = new StringStream(str);
    var cmap = CMapFactory.create(stream);
    expect(cmap.lookup(0x03)).toEqual(String.fromCharCode(0x00));
    expect(cmap.lookup(0x04)).toEqual(String.fromCharCode(0x01));
    expect(cmap.lookup(0x05)).toBeUndefined();
  });
  it('parses beginbfrange with range', function() {
    var str = '1 beginbfrange\n' +
              '<06> <0B> 0\n' +
              'endbfrange\n';
    var stream = new StringStream(str);
    var cmap = CMapFactory.create(stream);
    expect(cmap.lookup(0x05)).toBeUndefined();
    expect(cmap.lookup(0x06)).toEqual(String.fromCharCode(0x00));
    expect(cmap.lookup(0x0B)).toEqual(String.fromCharCode(0x05));
    expect(cmap.lookup(0x0C)).toBeUndefined();
  });
  it('parses beginbfrange with array', function() {
    var str = '1 beginbfrange\n' +
              '<0D> <12> [ 0 1 2 3 4 5 ]\n' +
              'endbfrange\n';
    var stream = new StringStream(str);
    var cmap = CMapFactory.create(stream);
    expect(cmap.lookup(0x0C)).toBeUndefined();
    expect(cmap.lookup(0x0D)).toEqual(0x00);
    expect(cmap.lookup(0x12)).toEqual(0x05);
    expect(cmap.lookup(0x13)).toBeUndefined();
  });
  it('parses begincidchar', function() {
    var str = '1 begincidchar\n' +
              '<14> 0\n' +
              'endcidchar\n';
    var stream = new StringStream(str);
    var cmap = CMapFactory.create(stream);
    expect(cmap.lookup(0x14)).toEqual(String.fromCharCode(0x00));
    expect(cmap.lookup(0x15)).toBeUndefined();
  });
  it('parses begincidrange', function() {
    var str = '1 begincidrange\n' +
              '<0016> <001B>   0\n' +
              'endcidrange\n';
    var stream = new StringStream(str);
    var cmap = CMapFactory.create(stream);
    expect(cmap.lookup(0x15)).toBeUndefined();
    expect(cmap.lookup(0x16)).toEqual(String.fromCharCode(0x00));
    expect(cmap.lookup(0x1B)).toEqual(String.fromCharCode(0x05));
    expect(cmap.lookup(0x1C)).toBeUndefined();
  });
  it('decodes codespace ranges', function() {
    var str = '1 begincodespacerange\n' +
              '<01> <02>\n' +
              '<00000003> <00000004>\n' +
              'endcodespacerange\n';
    var stream = new StringStream(str);
    var cmap = CMapFactory.create(stream);
    var c = cmap.readCharCode(String.fromCharCode(1), 0);
    expect(c[0]).toEqual(1);
    expect(c[1]).toEqual(1);
    c = cmap.readCharCode(String.fromCharCode(0, 0, 0, 3), 0);
    expect(c[0]).toEqual(3);
    expect(c[1]).toEqual(4);
  });
  it('decodes 4 byte codespace ranges', function() {
    var str = '1 begincodespacerange\n' +
              '<8EA1A1A1> <8EA1FEFE>\n' +
              'endcodespacerange\n';
    var stream = new StringStream(str);
    var cmap = CMapFactory.create(stream);
    var c = cmap.readCharCode(String.fromCharCode(0x8E, 0xA1, 0xA1, 0xA1), 0);
    expect(c[0]).toEqual(0x8EA1A1A1);
    expect(c[1]).toEqual(4);
  });
  it('read usecmap', function() {
    var str = '/Adobe-Japan1-1 usecmap\n';
    var stream = new StringStream(str);
    var cmap = CMapFactory.create(stream, null, '../../external/cmaps/');
    expect(cmap.useCMap).toBeDefined();
  });
  it('parses wmode', function() {
    var str = '/WMode 1 def\n';
    var stream = new StringStream(str);
    var cmap = CMapFactory.create(stream);
    expect(cmap.vertical).toEqual(true);
  });
  it('loads built in cmap', function() {
    CMapFactory.create(new Name('Adobe-Japan1-1'), '../../external/cmaps/',
                       null);
  });
});

