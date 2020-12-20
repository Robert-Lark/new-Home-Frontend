// import {Link} from "gatsby";
// import React from "react";
// import Img from 'gatsby-image'

// function SingleRelease({label}) {
//   return (
//     <div>
//       <Link to={`/label/${label.slug.current}`}>
//         <h2>{label.name}</h2>
//       </Link>
//       <p>{release.artists.map((artist) => artist.name)}</p>
//       <Img fluid={label.image.asset.fluid}/>
//     </div>
//   );
// }

// function Label({label}) {
//   return (
//     <div>
//       {label.map((label) => (
//         <SingleRelease key={label.id} release={label} />
//       ))}
//     </div>
//   );
// }

// export const query = graphql`
// query AllReleases {
//     releases: allSanityRelease {
//     nodes {
//       id
//       name
//       slug {
//         current
//       }
//       artists {
//         id
//         name
//       }
//       image {
//         asset {
//           fluid(maxWidth: 400) {
//             ...GatsbySanityImageFluid
//           }
          
//         }
//       }
//     }
//   }
// }
// `;

export default Label;