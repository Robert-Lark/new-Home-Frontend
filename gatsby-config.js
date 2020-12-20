const dotenv = require ('dotenv')

dotenv.config({path: 'env'})


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
    "gatsby-plugin-styled-components",
    "gatsby-plugin-sharp",
    "gatsby-transformer-sharp",
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
