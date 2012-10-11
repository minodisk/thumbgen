util = require 'util'
fs = require 'fs'
path = require 'path'
{spawn} = require 'child_process'
{Deferred} = require 'jsdeferred'
imagemagick = require 'imagemagick'
colors = require 'colors'


rmdir = (path)->
  dfd = new Deferred
  rm = spawn 'rm', ['-rf', path]
  out = ''
  err = ''
  rm.stdout.on 'data', (data)->
    out += data.toString 'utf8'
  rm.stderr.on 'data', (data)->
    err += data.toString 'utf8'
  rm.on 'exit', (code)->
    if err isnt ''
      dfd.fail err
    else
      dfd.call out
  dfd

mkdir = (path, mode = '0777')->
  dfd = new Deferred
  fs.mkdir path, mode, (err)->
    if err?
      dfd.fail err
      return
    dfd.call()
  dfd

readdir = (path)->
  dfd = new Deferred
  fs.readdir path, (err, files)->
    if err?
      dfd.fail err
      return
    dfd.call files
  dfd

copy = (from, to)->
  dfd = new Deferred
  util.pump fs.createReadStream(from), fs.createWriteStream(to), (err)->
    if err?
      dfd.fail err
      return
    dfd.call()
  dfd

identify = (path)->
  dfd = new Deferred
  imagemagick.identify path, (err, status)->
    if err?
      return dfd.fail err
    dfd.call status
  dfd

crop = (opts)->
  dfd = new Deferred
  imagemagick.crop opts, (err, stdout, stderr)->
    if err? or stderr isnt ''
      return dfd.fail err or stderr
    dfd.call stdout
  dfd

resize = (opts)->
  dfd = new Deferred
  imagemagick.resize opts, (err, stdout, stderr)->
    if err? or stderr isnt ''
      return dfd.fail err or stderr
    dfd.call stdout
  dfd


exports.run = run = ({input, output, width: dstWidth, height: dstHeight, scaleX, scaleY, mode, format, quality})->
  tmp = path.join output, '.tmp'

  Deferred
    .next(->
      rmdir tmp
    )
    .next(->
      mkdir tmp
    )
    .next(->
      readdir input
    )
    .next((files)->
      images = []
      movies = []
      for file in files
        if file.charAt(0) isnt '.'
          switch path.extname file
            when '.png', '.jpg', '.jpeg', '.gif'
              images.push file
            else
            #TODO check movie file
              movies.push file

      Deferred.parallel([
        copyImages input, tmp, images
        captureMovies input, tmp, movies
      ])
    )
    .next(->
      readdir tmp
    )
    .next((files)->
      len = files.length
      Deferred.loop(len, (i)->
        file = files[i]
        basename = path.basename file, path.extname file
        srcPath = path.join tmp, file
        dstPath = path.join output, "#{basename}.#{format}"

        identify(srcPath)
          .next(({width: srcWidth, height: srcHeight})->
            width = dstWidth
            height = dstWidth
            if scaleX? and not width?
              width = srcWidth * scaleX
            if scaleY? and not height?
              height = srcHeight * scaleY
            if width? and not height?
              height = width * srcHeight / srcWidth
            else if height? and not width?
              width = height * srcWidth / srcHeight
            width = Math.ceil width
            height = Math.ceil height

            options =
              srcPath: srcPath
              dstPath: dstPath
              format : format
              quality: quality

            switch mode
              when 'trim'
                options.width = width
                options.height = height
                crop options
              when 'min'
                if srcWidth / srcHeight < width / height
                  options.width = width
                  options.height = width * srcHeight / srcWidth
                else
                  options.width = height * srcWidth / srcHeight
                  options.height = height
                resize options
              when 'max'
                options.width = width
                options.height = height
                resize options
          )
          .next((stdout)->
            util.puts "[#{'INFO'.green}] #{i + 1}/#{len} #{dstPath}"
          )
          .error((err)->
            if err.stack?
              err = err.stack
            util.puts err.toString().red
          )
      )
    )
    .next(->
      rmdir tmp
    )
    .next(->
      util.puts "[#{'INFO'.green}] Complete!"
    )
    .error((err)->
      if err.stack?
        err = err.stack
      util.puts err.toString().red
    )

copyImages = (input, output, files)->
  dfd = new Deferred
  Deferred
    .loop(files.length, (i)->
      file = files[i]
      basename = path.basename file, path.extname file
      copy path.join(input, file), path.join(output, "#{basename}.png")
    )
    .next(->
      dfd.call()
    )
    .error((err)->
      dfd.fail err
    )
  dfd

captureMovies = (input, output, files)->
  dfd = new Deferred
  Deferred
    .loop(files.length, (i)->
      file = files[i]
      dfd = new Deferred
      basename = path.basename file, path.extname file
      ffmpeg = spawn 'ffmpeg', [
        '-i', path.join(input, file)
        '-f', 'image2'
        '-vcodec', 'png'
        '-ss', '0'
        '-an'
        '-deinterlace'
        path.join(output, "#{basename}.png")
      ]
      out = ''
      err = ''
      ffmpeg.stdout.on 'data', (data)->
        out += data.toString 'utf8'
      ffmpeg.stderr.on 'data', (data)->
        err += data.toString 'utf8'
      ffmpeg.on 'exit', (code)=>
        if err isnt ''
          dfd.fail err
          return
        dfd.call out
      dfd
    )
    .next(->
      dfd.call()
    )
    .error((err)->
      dfd.fail err
    )
  dfd


run
  input  : 'test/input'
  output : 'test/output'
  scaleX : 0.5
  mode   : 'max'
  format : 'png'
  quality: 0.8
