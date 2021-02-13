try
  module.exports = require('./config.local')
catch error
  module.exports =
    SRCOMP: process.env.SRCOMP_URL or 'https://www.studentrobotics.org/comp-api'
    WEB_PORT: process.env.PORT or 5001
    DEBUG: true
