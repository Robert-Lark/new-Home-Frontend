const dotenv = require("dotenv");

dotenv.config({path: "env"});

module.exports = {
  siteMetadata: {
    title: "New Home",
    siteUrl: "https://gatsby.newhome",
    description: "Your new Home for the music you love",
  },
  plugins: [
    {
      resolve: "gatsby-source-sanity",
      options: {
        projectId: "vcfngr79",
        dataset: "production",
        watchMode: true,
        token: process.env.SANITY_TOKEN,
      },
    },
    {
      resolve: `gatsby-plugin-modal-routing`,
      options: {
        // A selector to set react-modal's app root to, default is `#___gatsby`
        // See http://reactcommunity.org/react-modal/accessibility/#app-element
        appElement: "#___gatsby",

        // Object of props that will be passed to the react-modal container
        // See http://reactcommunity.org/react-modal/#usage
        modalProps: {
        },
      },
    },
    {
      resolve: `gatsby-plugin-google-fonts`,
      options: {
        fonts: [
          `Raleway\:300`,
          `Source Code Pro\:200, Cormorant Garamond\:300`,
        ],
        display: "swap",
      },
    },
    "gatsby-plugin-sass",
    "gatsby-plugin-styled-components",
    "gatsby-plugin-sharp",
    {
      resolve: "gatsby-source-filesystem",
      options: {
        name: "images",
        path: "./src/images/",
      },
      __key: "images",
    },
  ],
};
