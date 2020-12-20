import React from 'react';
import {graphql} from "gatsby";
import ReleasesList from "../components/ReleasesList";

function releases({data}) {
    const releases = data.releases.nodes
    return (
        <div>
   <ReleasesList releases={releases}/>
        </div>
    );
}

export default releases;




// import {graphql} from "gatsby";
// import React from "react";
// import ReleasesList from "../components/ReleasesList";

// function releases({data }) {
// console.log(data)
//     //const releases = data.releases.nodes
//   return <>
//   <ReleasesList releases = {releases}/>
//   </>
// }
export const query = graphql`
query AllReleases {
    releases: allSanityRelease {
    nodes {
      id
      name
      slug {
        current
      }
      artists {
        id
        name
      }
      image {
        asset {
          fluid(maxWidth: 400) {
            ...GatsbySanityImageFluid
          }
          
        }
      }
    }
  }
}
`;

// export default releases
