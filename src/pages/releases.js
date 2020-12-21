import React from "react";
import {graphql} from "gatsby";
import ReleasesList from "../components/ReleasesList";

function releases({data}) {
  const releases = data.releases.nodes;
  return (
    <div>
      <ReleasesList releases={releases} />
    </div>
  );
}

export default releases;

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
            fixed(width: 200, height: 200) {
              ...GatsbySanityImageFixed
            }
            fluid(maxWidth: 200) {
              ...GatsbySanityImageFluid
            }
          }
        }
      }
    }
  }
`;

// export default releases
