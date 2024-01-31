const plugin = require('tailwindcss/plugin')
module.exports = {
    content: [
        './app/views/**/*.html.erb',
        './app/helpers/**/*.rb',
        './app/assets/stylesheets/**/*.css',
        './app/javascript/**/*.js'
    ],
    theme: {
        extend: {
            textShadow: {
                sm: '0 1px 2px var(--tw-shadow-color)',
                DEFAULT: '0 2px 4px var(--tw-shadow-color)',
                lg: '0 8px 16px var(--tw-shadow-color)',
            },
        },
    },
    plugins: [
        plugin(function ({matchUtilities, theme}) {
            matchUtilities(
                {
                    'text-shadow': (value) => ({
                        textShadow: value,
                    }),
                },
                {values: theme('textShadow')}
            )
        }),
    ],
}
